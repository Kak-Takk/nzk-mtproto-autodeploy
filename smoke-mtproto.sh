#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  smoke-mtproto.sh — Smoke-тест MTProto Stealth Proxy
#  Проверяет: контейнер, SNI-роутинг, TCP-шейпинг, sysctl профиль
#  Использование: sudo bash smoke-mtproto.sh
# ─────────────────────────────────────────────────────────────────
set -uo pipefail

# ══════════════════════════════════════════════════════════════════
# ЦВЕТА
# ══════════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PASS=0
FAIL=0
WARN=0

ok()   { echo -e "  ${GREEN}✅ PASS${RESET}  $*"; ((PASS++)); }
fail() { echo -e "  ${RED}❌ FAIL${RESET}  $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠️  WARN${RESET}  $*"; ((WARN++)); }
info() { echo -e "  ${CYAN}ℹ️  INFO${RESET}  $*"; }
header() { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${RESET}"; }

# ══════════════════════════════════════════════════════════════════
# ЗАГРУЗКА КОНФИГУРАЦИИ
# ══════════════════════════════════════════════════════════════════
CONFIG="/root/.mtproto-proxy.conf"

if [[ ! -f "$CONFIG" ]]; then
    echo -e "${RED}Конфиг ${CONFIG} не найден. Сначала запустите deploy_mt.sh${RESET}"
    exit 1
fi

# Безопасный парсинг конфига (без source — не выполняем чужой код)
while IFS='=' read -r k v; do
    case "$k" in
        SERVER_IP|PROXY_PORT|FAKETLS_DOMAIN|CONTAINER_NAME|SNI_MODE|MTG_INTERNAL_PORT|STREAM_CONF|EXTERNAL_FALLBACK)
            printf -v "$k" '%s' "$v"
            ;;
    esac
done < <(grep -E '^(SERVER_IP|PROXY_PORT|FAKETLS_DOMAIN|CONTAINER_NAME|SNI_MODE|MTG_INTERNAL_PORT|STREAM_CONF|EXTERNAL_FALLBACK)=' "$CONFIG")

# Определяем интерфейс (как в deploy_mt.sh)
ETH_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '{printf $5}')
[[ -z "$ETH_IF" ]] && ETH_IF="eth0"

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     🔬 MTProto Stealth Proxy — Smoke Test       ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  ${DIM}Server: ${SERVER_IP}:${PROXY_PORT} | FakeTLS: ${FAKETLS_DOMAIN}${RESET}"
echo -e "  ${DIM}Container: ${CONTAINER_NAME} | SNI: ${SNI_MODE} | IF: ${ETH_IF}${RESET}"
echo ""

# ══════════════════════════════════════════════════════════════════
# 1. КОНТЕЙНЕР MTG
# ══════════════════════════════════════════════════════════════════
header "1. Docker-контейнер mtg"

# 1a. Контейнер запущен?
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    ok "Контейнер ${BOLD}${CONTAINER_NAME}${RESET} запущен"
else
    fail "Контейнер ${BOLD}${CONTAINER_NAME}${RESET} НЕ запущен"
fi

# 1b. Нет ли panic/fatal в логах?
LOG_ERRORS=$(docker logs --tail 100 "${CONTAINER_NAME}" 2>&1 | grep -icE 'panic|fatal|error|cannot|refused' || true)
if [[ "$LOG_ERRORS" -eq 0 ]]; then
    ok "Логи чистые (нет panic/fatal/error)"
else
    warn "В логах найдено ${BOLD}${LOG_ERRORS}${RESET} подозрительных строк"
    docker logs --tail 5 "${CONTAINER_NAME}" 2>&1 | while IFS= read -r line; do
        echo -e "       ${DIM}${line}${RESET}"
    done
fi

# 1c. Порт слушается?
if ss -tlnp | grep -q ":${PROXY_PORT} "; then
    ok "Порт ${BOLD}${PROXY_PORT}${RESET} слушается"
else
    fail "Порт ${BOLD}${PROXY_PORT}${RESET} НЕ слушается"
fi

# 1d. Docker security flags
CONTAINER_INSPECT=$(docker inspect "${CONTAINER_NAME}" 2>/dev/null)
if echo "$CONTAINER_INSPECT" | grep -q '"ReadonlyRootfs": true'; then
    ok "Контейнер read-only (--read-only)"
else
    warn "Контейнер НЕ read-only"
fi

PIDS_LIMIT=$(echo "$CONTAINER_INSPECT" | grep -oP '"PidsLimit":\s*\K[0-9]+' || echo "0")
if [[ "$PIDS_LIMIT" -ge 512 ]]; then
    ok "PidsLimit = ${BOLD}${PIDS_LIMIT}${RESET} (достаточно для Go)"
else
    warn "PidsLimit = ${BOLD}${PIDS_LIMIT}${RESET} (может быть мало для Go-приложения)"
fi

# ══════════════════════════════════════════════════════════════════
# 2. TCP-ПОДКЛЮЧЕНИЕ И SNI
# ══════════════════════════════════════════════════════════════════
header "2. TCP-подключение и TLS SNI"

# 2a. TCP connect к порту 443
if timeout 5 bash -c "echo >/dev/tcp/${SERVER_IP}/${PROXY_PORT}" 2>/dev/null; then
    ok "TCP connect к ${BOLD}${SERVER_IP}:${PROXY_PORT}${RESET} успешен"
else
    fail "TCP connect к ${BOLD}${SERVER_IP}:${PROXY_PORT}${RESET} не удался"
fi

# 2b. TLS handshake с FAKETLS_DOMAIN (должен попасть в mtg)
if command -v openssl &>/dev/null; then
    TLS_OUTPUT=$(echo | timeout 5 openssl s_client -servername "${FAKETLS_DOMAIN}" -connect "${SERVER_IP}:${PROXY_PORT}" 2>&1 || true)
    
    # mtg при FakeTLS проксирует TLS до реального сервера —
    # проверяем что получен реальный сертификат (а не просто TCP connect)
    if echo "$TLS_OUTPUT" | grep -qiE 'subject=|issuer='; then
        ok "TLS handshake с SNI=${BOLD}${FAKETLS_DOMAIN}${RESET} — сертификат получен"
    elif echo "$TLS_OUTPUT" | grep -qiE 'CONNECTED'; then
        ok "TLS к SNI=${BOLD}${FAKETLS_DOMAIN}${RESET} — TCP OK (mtg FakeTLS перехватил)"
    else
        warn "TLS handshake с SNI=${BOLD}${FAKETLS_DOMAIN}${RESET} — неожиданный ответ"
        echo "$TLS_OUTPUT" | head -3 | while IFS= read -r line; do
            echo -e "       ${DIM}${line}${RESET}"
        done
    fi
    
    # 2c. TLS handshake с RANDOM доменом (должен попасть на fallback / сайт)
    RANDOM_DOMAIN="random-scanner-$(date +%s).example.com"
    TLS_RANDOM=$(echo | timeout 5 openssl s_client -servername "${RANDOM_DOMAIN}" -connect "${SERVER_IP}:${PROXY_PORT}" 2>&1 || true)
    
    if echo "$TLS_RANDOM" | grep -qiE 'subject=|issuer='; then
        ok "Сканер-тест (SNI=${BOLD}${RANDOM_DOMAIN}${RESET}) → перенаправлен на fallback"
        
        # Дополнительно: проверяем что fallback реально отвечает HTTP
        if command -v curl &>/dev/null; then
            FALLBACK_HTTP=$(curl -sk --resolve "${RANDOM_DOMAIN}:${PROXY_PORT}:${SERVER_IP}" \
                -o /dev/null -w '%{http_code}' \
                "https://${RANDOM_DOMAIN}:${PROXY_PORT}/" --max-time 5 2>/dev/null || echo "000")
            if [[ "$FALLBACK_HTTP" != "000" ]]; then
                ok "Fallback HTTP ответ: ${BOLD}${FALLBACK_HTTP}${RESET} (сканер видит белый сайт)"
            else
                info "Fallback не вернул HTTP (TLS-уровень работает, HTTP необязателен)"
            fi
        fi
    else
        info "Сканер-тест → fallback не ответил (нормально если external_fallback недоступен)"
    fi
else
    warn "openssl не установлен — пропускаю TLS-тесты"
fi

# 2d. Проверка nginx (если SNI_MODE)
if [[ "${SNI_MODE}" == "true" ]]; then
    if systemctl is-active --quiet nginx; then
        ok "Nginx запущен (SNI-режим)"
    else
        fail "Nginx НЕ запущен (SNI-режим активен, но nginx мёртв!)"
    fi
    
    if [[ -f "${STREAM_CONF:-/etc/nginx/stream_mtproxy.conf}" ]]; then
        ok "Stream-конфиг ${BOLD}${STREAM_CONF}${RESET} существует"
    else
        fail "Stream-конфиг НЕ найден"
    fi
fi

# ══════════════════════════════════════════════════════════════════
# 3. IPTABLES / TCP STEALTH PROFILE
# ══════════════════════════════════════════════════════════════════
header "3. TCP Stealth Profile (iptables + sysctl)"

# 3a. iptables MSS clamping
if iptables -t mangle -C POSTROUTING -p tcp --sport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850 2>/dev/null; then
    ok "iptables POSTROUTING MSS=850 для sport ${BOLD}${PROXY_PORT}${RESET}"
else
    fail "iptables POSTROUTING MSS rule НЕ найдено"
fi

if iptables -t mangle -C PREROUTING -p tcp --dport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850 2>/dev/null; then
    ok "iptables PREROUTING MSS=850 для dport ${BOLD}${PROXY_PORT}${RESET}"
else
    fail "iptables PREROUTING MSS rule НЕ найдено"
fi

# 3b. tc netem — должен быть ОТКЛЮЧЁН (RTT fingerprint опасен для DPI)
TC_NETEM=$(tc qdisc show dev "${ETH_IF}" 2>/dev/null | grep netem || echo "отсутствует")
if [[ "$TC_NETEM" == "отсутствует" ]]; then
    ok "tc netem ОТКЛЮЧЁН на ${BOLD}${ETH_IF}${RESET} (RTT fingerprint safe ✅)"
else
    fail "tc netem АКТИВЕН на ${BOLD}${ETH_IF}${RESET} — УДАЛИТЕ! (RTT fingerprint для DPI)"
fi

# 3d. sysctl BBR
CONGESTION=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
if [[ "$CONGESTION" == "bbr" ]]; then
    ok "TCP congestion: ${BOLD}BBR${RESET}"
else
    warn "TCP congestion: ${BOLD}${CONGESTION}${RESET} (ожидается bbr)"
fi

# 3e. sysctl file-max
FILE_MAX=$(sysctl -n fs.file-max 2>/dev/null || echo "0")
if [[ "$FILE_MAX" -ge 2097152 ]]; then
    ok "fs.file-max = ${BOLD}${FILE_MAX}${RESET}"
else
    warn "fs.file-max = ${BOLD}${FILE_MAX}${RESET} (ожидается ≥2097152)"
fi

# 3f. sysctl tcp_fin_timeout
FIN_TIMEOUT=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo "60")
if [[ "$FIN_TIMEOUT" -le 15 ]]; then
    ok "tcp_fin_timeout = ${BOLD}${FIN_TIMEOUT}${RESET}"
else
    warn "tcp_fin_timeout = ${BOLD}${FIN_TIMEOUT}${RESET} (ожидается ≤15)"
fi

# ══════════════════════════════════════════════════════════════════
# 4. TELEGRAM CONNECTIVITY (базовый)
# ══════════════════════════════════════════════════════════════════
header "4. Telegram connectivity"

# 4a. Прямое TCP к Telegram DC
TG_DC="149.154.167.50"
TG_DC_PORT=443

if timeout 5 bash -c "echo >/dev/tcp/${TG_DC}/${TG_DC_PORT}" 2>/dev/null; then
    ok "Прямое TCP-подключение к Telegram DC (${BOLD}${TG_DC}:${TG_DC_PORT}${RESET})"
else
    warn "Telegram DC ${TG_DC} недоступен напрямую (может быть заблокирован)"
fi

# 4b. mtg статус в логах
MTG_LOGS=$(docker logs --tail 50 "${CONTAINER_NAME}" 2>&1)
if echo "$MTG_LOGS" | grep -qiE 'started|listening|running|ready'; then
    ok "mtg сообщает о готовности (started/listening)"
else
    info "mtg не показал явного 'started' в последних логах"
fi

# 4c. Проверка что mtg реально проксирует (raw TCP через наш порт к DC)
# Отправляем TLS ClientHello с SNI=FAKETLS_DOMAIN — mtg должен принять и проксировать
if command -v openssl &>/dev/null; then
    # Подключаемся с нашим FakeTLS доменом — mtg должен ответить (не сбросить соединение)
    MTG_CONNECT=$(echo | timeout 5 openssl s_client \
        -servername "${FAKETLS_DOMAIN}" \
        -connect "127.0.0.1:${MTG_INTERNAL_PORT:-1443}" 2>&1 || true)
    
    # Если мы на этом же сервере и mtg слушает на internal port — проверяем
    if echo "$MTG_CONNECT" | grep -qiE 'CONNECTED'; then
        ok "mtg принимает TLS на localhost:${BOLD}${MTG_INTERNAL_PORT:-1443}${RESET} (прокси жив)"
    elif ss -tlnp | grep -q ":${MTG_INTERNAL_PORT:-1443} "; then
        ok "mtg слушает на localhost:${BOLD}${MTG_INTERNAL_PORT:-1443}${RESET}"
    else
        info "mtg internal port не доступен напрямую (нормально в direct-режиме)"
    fi
fi

# 4d. Проверяем ресурсы контейнера (без docker exec — безопасно для read-only)
MTG_MEM=$(docker stats --no-stream --format '{{.MemUsage}}' "${CONTAINER_NAME}" 2>/dev/null || echo "N/A")
if [[ "$MTG_MEM" != "N/A" && -n "$MTG_MEM" ]]; then
    ok "mtg потребление памяти: ${BOLD}${MTG_MEM}${RESET}"
else
    info "Не удалось получить stats контейнера"
fi

# ══════════════════════════════════════════════════════════════════
# 5. ТРАФИК-ТЕСТ: Анализ реального поведения (tcpdump + метрики)
# ══════════════════════════════════════════════════════════════════
header "5. Traffic Analysis (tcpdump + stealth metrics)"

if ! command -v tcpdump &>/dev/null; then
    warn "tcpdump не установлен — пропускаю анализ трафика"
    info "Установите: ${BOLD}apt install tcpdump${RESET}"
else
    PCAP_FILE="/tmp/mtproto_smoke_$$.pcap"

    # 5a. Генерируем реальный TLS-трафик к нашему порту (openssl connect)
    info "Генерируем тестовый трафик (5 сек)..."

    # Гарантированное удаление pcap при сбое
    trap '[[ -n "${TCPDUMP_PID:-}" ]] && kill "${TCPDUMP_PID}" 2>/dev/null; rm -f "${PCAP_FILE}"' EXIT INT TERM

    # Слушаем 'any', чтобы ловить трафик с этого же сервера на свой IP
    tcpdump -i any -n -c 30 -w "${PCAP_FILE}" "tcp port ${PROXY_PORT}" &>/dev/null &
    TCPDUMP_PID=$!
    sleep 1

    # Генерируем трафик — несколько TLS-connect с нашим SNI
    pids=()
    for i in 1 2 3; do
        (echo -e "GET / HTTP/1.1\r\nHost: ${FAKETLS_DOMAIN}\r\n\r\n" | timeout 3 openssl s_client -servername "${FAKETLS_DOMAIN}" \
            -connect "${SERVER_IP}:${PROXY_PORT}" &>/dev/null || true) &
        pids+=($!)
    done
    # + один connect с рандомным SNI (fallback трафик)
    (echo -e "GET / HTTP/1.1\r\nHost: scan-test.example.com\r\n\r\n" | timeout 3 openssl s_client -servername "scan-test.example.com" \
        -connect "${SERVER_IP}:${PROXY_PORT}" &>/dev/null || true) &
    pids+=($!)

    # Ждем ТОЛЬКО генераторы трафика (не tcpdump — решает проблему зависания)
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    sleep 2

    # Останавливаем tcpdump
    kill "${TCPDUMP_PID}" 2>/dev/null || true
    wait "${TCPDUMP_PID}" 2>/dev/null || true
    trap - EXIT INT TERM

    # 5b. Анализируем захват
    if [[ -f "${PCAP_FILE}" && -s "${PCAP_FILE}" ]]; then
        PACKETS=$(tcpdump -r "${PCAP_FILE}" -n 2>/dev/null | wc -l)

        if [[ "$PACKETS" -gt 0 ]]; then
            ok "tcpdump захватил ${BOLD}${PACKETS}${RESET} пакетов на ${ETH_IF}:${PROXY_PORT}"
        else
            warn "tcpdump не захватил пакетов"
        fi

        # 5c. MSS в SYN-пакетах
        MSS_VALUES=$(tcpdump -r "${PCAP_FILE}" -n -v 'tcp[tcpflags] & (tcp-syn) != 0' 2>/dev/null \
            | grep -oP 'mss \K[0-9]+' | sort -u | tr '\n' ' ')
        if [[ -n "$MSS_VALUES" ]]; then
            if echo "$MSS_VALUES" | grep -q "850"; then
                ok "MSS clamping в SYN: ${BOLD}${MSS_VALUES}${RESET}(содержит 850 ✅)"
            else
                warn "MSS в SYN: ${BOLD}${MSS_VALUES}${RESET}(ожидается 850)"
            fi
        else
            info "MSS не обнаружен в SYN (мало пакетов или нет SYN)"
        fi

        # 5d. Разнообразие размеров пакетов (не должен быть моно-паттерн)
        UNIQUE_SIZES=$(tcpdump -r "${PCAP_FILE}" -n 2>/dev/null \
            | awk 'match($0,/length ([0-9]+)/,m){print m[1]}' | sort -n | uniq | wc -l)
        if [[ "$UNIQUE_SIZES" -ge 3 ]]; then
            ok "Разнообразие размеров пакетов: ${BOLD}${UNIQUE_SIZES}${RESET} уникальных (нет моно-паттерна)"
        else
            info "Уникальных размеров: ${BOLD}${UNIQUE_SIZES}${RESET}"
        fi

        # 5e. Jitter (анализ интервалов между пакетами)
        TIMING=$(tcpdump -r "${PCAP_FILE}" -n -ttt 2>/dev/null \
            | awk 'NR>1 {split($1, a, ":"); t=a[1]*3600+a[2]*60+a[3]; sum+=t; cnt++} END {if(cnt>0) printf "%.4f", sum/cnt; else print "N/A"}')
        if [[ "$TIMING" != "N/A" && -n "$TIMING" ]]; then
            info "Средний интервал между пакетами: ${BOLD}${TIMING}s${RESET} (естественный jitter сети/BBR)"
        fi

        # 5f. tshark — SNI в ClientHello (если установлен)
        if command -v tshark &>/dev/null; then
            SNI_LIST=$(tshark -r "${PCAP_FILE}" -Y "tls.handshake.type == 1" \
                -T fields -e tls.handshake.extensions_server_name 2>/dev/null \
                | sort | uniq -c | sort -rn | head -5)
            if [[ -n "$SNI_LIST" ]]; then
                ok "TLS ClientHello SNI (tshark):"
                echo "$SNI_LIST" | while IFS= read -r sni_line; do
                    echo -e "       ${DIM}${sni_line}${RESET}"
                done
                if echo "$SNI_LIST" | grep -q "${FAKETLS_DOMAIN}"; then
                    ok "FakeTLS домен ${BOLD}${FAKETLS_DOMAIN}${RESET} присутствует в SNI ✅"
                fi
            else
                info "tshark не нашёл ClientHello в захвате"
            fi
        else
            info "tshark не установлен — SNI-анализ пропущен (${DIM}apt install tshark${RESET})"
        fi

        rm -f "${PCAP_FILE}"
    else
        warn "Файл захвата пуст или не создан"
        rm -f "${PCAP_FILE}" 2>/dev/null
    fi
fi

# ══════════════════════════════════════════════════════════════════
# ИТОГ
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

TOTAL=$((PASS + FAIL + WARN))

echo -e "  ${GREEN}✅ PASS: ${BOLD}${PASS}${RESET}  ${RED}❌ FAIL: ${BOLD}${FAIL}${RESET}  ${YELLOW}⚠️  WARN: ${BOLD}${WARN}${RESET}  │  Total: ${TOTAL}"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    if [[ "$WARN" -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}🎉 ВСЕ ТЕСТЫ ПРОЙДЕНЫ! Прокси полностью готов к бою.${RESET}"
    else
        echo -e "  ${GREEN}${BOLD}✅ Критических проблем нет.${RESET} ${YELLOW}Есть предупреждения — см. выше.${RESET}"
    fi
else
    echo -e "  ${RED}${BOLD}⛔ Обнаружены проблемы! Проверьте FAIL-пункты выше.${RESET}"
fi

echo ""
echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S %Z') | smoke-mtproto.sh${RESET}"
echo ""
