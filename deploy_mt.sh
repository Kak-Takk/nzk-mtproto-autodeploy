#!/usr/bin/env bash
#  deploy_mt.sh — MTProto FakeTLS Proxy Deployer
#  GENERATED FILE — DO NOT EDIT DIRECTLY

# >>> BEGIN lib/common.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/common.sh — Общий фундамент: strict mode, цвета, иконки, логгеры, константы
# ══════════════════════════════════════════════════════════════════

# ── Strict Mode ──

# ── Цвета ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Иконки (UTF-8) ──
ICON_OK="✅"
ICON_ERR="❌"
ICON_WARN="⚠️ "
ICON_INFO="ℹ️ "
ICON_ROCKET="🚀"
ICON_GEAR="⚙️ "
ICON_KEY="🔑"
ICON_LINK="🔗"
ICON_CHECK="✔"
ICON_DOCKER="🐳"
ICON_SHIELD="🛡️ "
ICON_CLOCK="⏱️ "

# ── Логгеры ──
log_info()    { echo -e "${BLUE}${ICON_INFO}  [INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}${ICON_OK} [  OK ]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}${ICON_WARN} [WARN]${RESET}  $*"; }
log_err()     { echo -e "${RED}${ICON_ERR} [ ERR]${RESET}  $*"; }
log_step()    { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${RESET}"; }
log_sub()     { echo -e "    ${CYAN}▸${RESET} $*"; }
log_dim()     { echo -e "    ${WHITE}$*${RESET}"; }
separator()   { echo -e "${GRAY}$(printf '─%.0s' {1..60})${RESET}"; }

# ── Readonly-константы ──
readonly CONFIG_FILE="/root/.mtproto-proxy.conf"
readonly CONTAINER_NAME="mtproto-proxy"
readonly MTG_IMAGE="nineseconds/mtg:2"
readonly DNS_RESOLVER="1.1.1.1"
readonly ULIMIT_NOFILE=51200
readonly EXTERNAL_FALLBACK="www.microsoft.com:443"
readonly STREAM_CONF="/etc/nginx/stream_mtproxy.conf"
readonly NGINX_SITE_PORT=8443
readonly MTG_INTERNAL_PORT=1443
readonly FALLBACK_PORT=8443
readonly SYSCTL_CONF="/etc/sysctl.d/99-mtproxy-stealth.conf"
readonly REALIP_CONF="/etc/nginx/conf.d/99-mtproto-realip.conf"
readonly ROTATE_SCRIPT="/root/rotate_fallback.sh"

# Telemt (Rust) — новый движок
readonly TELEMT_IMAGE="ghcr.io/telemt/telemt:latest"
readonly TELEMT_CONFIG_DIR="/root/.telemt"
readonly TELEMT_CONFIG_FILE="/root/.telemt/config.toml"

# РФ-дружественные домены (РКН не блочит, ASN безопасен)
readonly RF_DOMAINS=("yandex.ru" "mail.ru" "ok.ru" "sberbank.ru" "beeline.ru" "rambler.ru" "rutube.ru")

# ── Mutable runtime state ──
PROXY_PORT="${PROXY_PORT:-443}"
FAKETLS_DOMAIN=""
SNI_MODE=false
SERVER_IP="${SERVER_IP:-}"
SECRET=""
PROXY_ENGINE="${PROXY_ENGINE:-telemt}"  # "telemt" (Rust, рекомендуется) или "mtg" (Go, legacy)

# <<< END lib/common.sh <<<

# >>> BEGIN lib/config.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/config.sh — Конфигурация: safe-loader, save, validate, update
# ══════════════════════════════════════════════════════════════════

# Whitelist допустимых ключей конфига
readonly CONFIG_KEYS="SERVER_IP|PROXY_PORT|FAKETLS_DOMAIN|EXTERNAL_FALLBACK|SECRET|CONTAINER_NAME|MTG_IMAGE|SNI_MODE|MTG_INTERNAL_PORT|STREAM_CONF|ENGINE"

# ── Проверка наличия конфига ──
config_exists() {
    [[ -f "$CONFIG_FILE" ]]
}

# ── Безопасная загрузка конфига (без source) ──
load_config_safe() {
    [[ -f "$CONFIG_FILE" ]] || return 1

    while IFS='=' read -r k v; do
        # Убираем возможные пробелы и кавычки
        v="${v%\"}"
        v="${v#\"}"
        v="${v%\'}"
        v="${v#\'}"

        case "$k" in
            SERVER_IP)          SERVER_IP="$v" ;;
            PROXY_PORT)         PROXY_PORT="$v" ;;
            FAKETLS_DOMAIN)     FAKETLS_DOMAIN="$v" ;;
            SECRET)             SECRET="$v" ;;
            SNI_MODE)           SNI_MODE="$v" ;;
            ENGINE)             PROXY_ENGINE="$v" ;;
            # Остальные ключи — в переменные, но не перезаписываем readonly
        esac
    done < <(grep -E "^(${CONFIG_KEYS})=" "$CONFIG_FILE" 2>/dev/null)
}

# ── Валидация загруженного конфига ──
validate_loaded_config() {
    local valid=true

    if [[ -z "${SERVER_IP:-}" ]]; then
        log_warn "Конфиг: SERVER_IP пуст"
        valid=false
    fi

    if [[ -z "${SECRET:-}" ]]; then
        log_warn "Конфиг: SECRET пуст"
        valid=false
    fi

    if [[ -z "${FAKETLS_DOMAIN:-}" ]]; then
        log_warn "Конфиг: FAKETLS_DOMAIN пуст"
        valid=false
    fi

    [[ "$valid" == true ]]
}

# ── Сохранение конфига ──
save_config() {
    cat > "$CONFIG_FILE" << EOF
# MTProto Proxy Config — created $(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=${SERVER_IP}
PROXY_PORT=${PROXY_PORT}
FAKETLS_DOMAIN=${FAKETLS_DOMAIN}
EXTERNAL_FALLBACK=${EXTERNAL_FALLBACK}
SECRET=${SECRET}
CONTAINER_NAME=${CONTAINER_NAME}
MTG_IMAGE=${MTG_IMAGE}
SNI_MODE=${SNI_MODE}
MTG_INTERNAL_PORT=${MTG_INTERNAL_PORT}
STREAM_CONF=${STREAM_CONF}
ENGINE=${PROXY_ENGINE}
EOF
    chmod 600 "$CONFIG_FILE"
    log_ok "Конфигурация сохранена в ${BOLD}${CONFIG_FILE}${RESET}"
}

# ── Обновление одного ключа в конфиге ──
update_config_key() {
    local key="$1"
    local value="$2"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_err "Конфиг не найден: $CONFIG_FILE"
        return 1
    fi

    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

# ── Выбор FakeTLS домена ──
select_faketls_domain() {
    # Если уже задан (через конфиг при обновлении) — не трогаем
    if [[ -n "${FAKETLS_DOMAIN}" ]]; then
        return 0
    fi

    # Всегда берём RF-домен: в SNI-режиме домен сайта вызовет конфликт в nginx map,
    # а в direct-режиме у пользователя нет своих доменов на сервере.
    FAKETLS_DOMAIN="${RF_DOMAINS[$RANDOM % ${#RF_DOMAINS[@]}]}"
    log_ok "FakeTLS домен: ${BOLD}${FAKETLS_DOMAIN}${RESET} (рандом из RF-списка)"
}

# ══════════════════════════════════════════════════════════════════
# Telemt-специфичные функции конфигурации
# ══════════════════════════════════════════════════════════════════

# ── Конвертация ee-секрета mtg в 32-hex для Telemt ──
# mtg secret: ee + hex(domain) + 32_hex_random → нужно извлечь 32 hex-символа
# Если секрет уже 32 hex — возвращаем как есть
convert_mtg_secret_to_telemt() {
    local mtg_secret="$1"

    # Если секрет уже в формате 32-hex (Telemt native) — возвращаем
    if [[ ${#mtg_secret} -eq 32 ]] && [[ "$mtg_secret" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "$mtg_secret"
        return 0
    fi

    # mtg ee-secret: первые 2 символа 'ee', потом hex(domain), потом 32 символа секрета
    # Нам нужны первые 32 hex-символа после 'ee' префикса
    # Но проще сгенерировать новый чистый 32-hex
    # При миграции генерируем новый секрет — это необходимо, т.к. формат несовместим
    local new_secret
    new_secret=$(openssl rand -hex 16)
    echo "$new_secret"
}

# ── Генерация config.toml для Telemt ──
generate_telemt_config() {
    log_step "${ICON_GEAR} Генерация конфигурации Telemt"

    mkdir -p "${TELEMT_CONFIG_DIR}"

    # Определяем порт для listener
    local listen_port=443
    if [[ "$SNI_MODE" == true ]]; then
        listen_port=${MTG_INTERNAL_PORT}
    fi

    cat > "${TELEMT_CONFIG_FILE}" << TOMLEOF
### Telemt Config — generated by deploy_mt.sh $(date '+%Y-%m-%d %H:%M:%S')
log_level = "normal"

[server.api]
enabled = false

[[server.listeners]]
ip = "0.0.0.0"
port = ${listen_port}

[censorship]
tls_domain = "${FAKETLS_DOMAIN}"
mask = true
tls_emulation = true
tls_front_dir = "/app/tlsfront"

[performance]
download_buffer_size = 131072
me_pool_size = 8
workers = 2

[access.users]
admin = "${SECRET}"
TOMLEOF

    chmod 644 "${TELEMT_CONFIG_FILE}"
    log_ok "Конфиг Telemt создан: ${BOLD}${TELEMT_CONFIG_FILE}${RESET}"
    log_sub "TLS-домен: ${FAKETLS_DOMAIN}"
    log_sub "Маскировка (TCP Splicing): включена"
    log_sub "TLS-эмуляция: включена"
}

# <<< END lib/config.sh <<<

# >>> BEGIN lib/system.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/system.sh — Системные проверки: root, OS, зависимости, Docker, IP
# ══════════════════════════════════════════════════════════════════

# ── Проверка root ──
check_root() {
    log_step "${ICON_SHIELD} Проверка привилегий"
    if [[ $EUID -ne 0 ]]; then
        log_err "Этот скрипт требует привилегий root."
        log_sub "Запустите: ${BOLD}sudo ./deploy_mt.sh${RESET}"
        exit 1
    fi
    log_ok "Запущен от root"
}

# ── Определение ОС ──
detect_os() {
    log_step "${ICON_GEAR} Определение операционной системы"

    if [[ ! -f /etc/os-release ]]; then
        log_err "Не удалось определить ОС. Поддерживаются Ubuntu/Debian."
        exit 1
    fi

    source /etc/os-release
    OS_NAME="${ID}"
    OS_VERSION="${VERSION_ID:-unknown}"

    log_ok "ОС: ${BOLD}${PRETTY_NAME}${RESET}"

    case "$OS_NAME" in
        ubuntu|debian)
            log_sub "Поддерживаемая ОС ${ICON_CHECK}"
            ;;
        *)
            log_warn "ОС ${OS_NAME} официально не тестировалась. Продолжаем..."
            ;;
    esac
}

# ── Проверка и установка зависимостей ──
check_dependencies() {
    log_step "${ICON_GEAR} Проверка зависимостей"

    # Required — без них скрипт не работает
    local required_deps=("curl" "iptables" "grep" "awk" "sed" "ss" "ip")
    # Optional — деградация без ошибки
    local optional_deps=("tcpdump" "openssl" "tshark")

    local deps_missing=()

    # Проверяем required
    for dep in "${required_deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            log_ok "${dep} $(command -v "$dep")"
        else
            log_warn "${dep} — не найден"
            deps_missing+=("$dep")
        fi
    done

    # Проверяем optional (только warn)
    for dep in "${optional_deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            log_ok "${dep} $(command -v "$dep")"
        else
            log_dim "${dep} — не найден (опционально)"
        fi
    done

    # Установка отсутствующих required
    if [[ ${#deps_missing[@]} -gt 0 ]]; then
        # Маппинг бинарников к пакетам (ss/ip/tc → iproute2)
        local pkgs_to_install=()
        local pkg_name
        for dep in "${deps_missing[@]}"; do
            case "$dep" in
                ss|ip|tc) pkg_name="iproute2" ;;
                *) pkg_name="$dep" ;;
            esac
            # Дедупликация
            if [[ ! " ${pkgs_to_install[*]} " =~ \ ${pkg_name}\  ]]; then
                pkgs_to_install+=("$pkg_name")
            fi
        done
        log_info "Установка недостающих: ${pkgs_to_install[*]}"
        apt-get update -qq
        apt-get install -y -qq "${pkgs_to_install[@]}"
        log_ok "Зависимости установлены"
    else
        log_ok "Все базовые зависимости в порядке"
    fi
}

# ── Docker — установка / проверка ──
ensure_docker() {
    log_step "${ICON_DOCKER} Docker"

    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        log_ok "Docker уже установлен: ${BOLD}v${docker_ver}${RESET}"
    else
        log_info "Docker не найден. Устанавливаю..."
        curl -fsSL https://get.docker.com | sh
        log_ok "Docker установлен"
    fi

    # Убедимся, что демон запущен
    if ! systemctl is-active --quiet docker; then
        log_info "Запускаю Docker daemon..."
        systemctl enable docker
        systemctl start docker
    fi
    log_ok "Docker daemon запущен"

    # Проверка socket
    if docker info &>/dev/null; then
        log_ok "Docker socket доступен"
    else
        log_err "Нет доступа к Docker socket"
        exit 1
    fi
}

# ── Определение внешнего IP ──
detect_ip() {
    log_step "${ICON_INFO} Определение внешнего IP-адреса"

    # Если IP задан вручную через env, используем его
    if [[ -n "${SERVER_IP:-}" ]]; then
        log_ok "Внешний IP задан вручную: ${BOLD}${SERVER_IP}${RESET}"
        return 0
    fi

    local services=("ifconfig.me" "api.ipify.org" "ipecho.net/plain" "icanhazip.com")

    for svc in "${services[@]}"; do
        SERVER_IP=$(curl -4 -s --max-time 5 "$svc" 2>/dev/null || true)
        if [[ -n "$SERVER_IP" && "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_ok "Внешний IP: ${BOLD}${SERVER_IP}${RESET} (via ${svc})"
            return 0
        fi
    done

    log_err "Не удалось определить внешний IP."
    log_sub "Укажите вручную: SERVER_IP=1.2.3.4 ./deploy_mt.sh"
    exit 1
}

# ── Helper: определение сетевого интерфейса ──
detect_network_interface() {
    local iface
    iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{printf $5}')
    if [[ -z "$iface" ]]; then
        iface="eth0"
    fi
    echo "$iface"
}

# <<< END lib/system.sh <<<

# >>> BEGIN lib/docker.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/docker.sh — Docker-логика: secret, контейнер, health check
# Поддержка двух движков: mtg (Go, legacy) и telemt (Rust)
# ══════════════════════════════════════════════════════════════════

# ── Генерация FakeTLS секрета (MTG) ──
generate_secret() {
    log_step "${ICON_KEY} Генерация FakeTLS секрета (домен: ${FAKETLS_DOMAIN})"

    log_info "Вытягиваю образ ${MTG_IMAGE}..."
    docker pull "${MTG_IMAGE}" 2>&1 | tail -1

    # mtg generate-secret — локальная операция (хеш + hostname), не сетевой тест
    SECRET=$(docker run --rm "${MTG_IMAGE}" generate-secret "${FAKETLS_DOMAIN}" 2>/dev/null | tail -1 || true)

    if [[ -z "$SECRET" || ${#SECRET} -lt 32 ]]; then
        log_err "Не удалось сгенерировать секрет. Проверьте Docker."
        exit 1
    fi

    log_ok "Секрет сгенерирован: ${BOLD}${SECRET:0:16}...${RESET}"
    log_dim "Полный секрет сохранён для ссылки ниже"
}

# ── Генерация секрета (Telemt) ──
# Не требует Docker — использует openssl, формат: 32 hex-символа
generate_secret_telemt() {
    log_step "${ICON_KEY} Генерация Telemt секрета (домен: ${FAKETLS_DOMAIN})"

    SECRET=$(openssl rand -hex 16)

    if [[ -z "$SECRET" || ${#SECRET} -ne 32 ]]; then
        log_err "Не удалось сгенерировать секрет. Проверьте openssl."
        exit 1
    fi

    log_ok "Секрет (32-hex): ${BOLD}${SECRET:0:16}...${RESET}"
    log_dim "Telemt использует прямой hex-секрет (без ee-префикса mtg)"
}

# ── Удаление старого контейнера ──
cleanup_old() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Удаляю старый контейнер ${CONTAINER_NAME}..."
        docker rm -f "${CONTAINER_NAME}" &>/dev/null
        log_ok "Старый контейнер удалён"
    fi
}

# ── Единый helper запуска контейнера mtg ──
# Использовать из deploy И rotate — убирает дублирование
docker_run_mtg() {
    local secret="$1"
    local port_mapping="$2"

    docker run -d \
        --name "${CONTAINER_NAME}" \
        --restart unless-stopped \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=16m \
        --security-opt no-new-privileges \
        --pids-limit 1024 \
        --memory 256m \
        --cpus 0.75 \
        --ulimit "nofile=${ULIMIT_NOFILE}:${ULIMIT_NOFILE}" \
        -p "${port_mapping}" \
        "${MTG_IMAGE}" \
        simple-run -n "${DNS_RESOLVER}" -i prefer-ipv4 "0.0.0.0:443" "${secret}"
}

# ── Единый helper запуска контейнера Telemt (Rust) ──
docker_run_telemt() {
    local port_mapping="$1"

    # Создаём директории для кэша TLS-эмуляции и метрик
    # 777 — контейнер работает под non-root UID, нужен write access
    mkdir -p /root/.telemt/cache /root/.telemt/tlsfront
    chmod 777 /root/.telemt/cache /root/.telemt/tlsfront

    log_info "Вытягиваю образ ${TELEMT_IMAGE}..."
    docker pull "${TELEMT_IMAGE}" 2>&1 | tail -1

    docker run -d \
        --name "${CONTAINER_NAME}" \
        --restart unless-stopped \
        --security-opt no-new-privileges \
        --pids-limit 1024 \
        --memory 256m \
        --cpus 0.75 \
        --ulimit nofile=65536:65536 \
        -v "${TELEMT_CONFIG_FILE}:/app/config.toml:ro" \
        -v "/root/.telemt/cache:/app/cache" \
        -v "/root/.telemt/tlsfront:/app/tlsfront" \
        -p "${port_mapping}" \
        "${TELEMT_IMAGE}"
}

# ── Определение port mapping ──
compose_port_mapping() {
    if [[ "$SNI_MODE" == true ]]; then
        echo "127.0.0.1:${MTG_INTERNAL_PORT}:443"
    else
        echo "${PROXY_PORT}:443"
    fi
}

# ── Запуск контейнера ──
launch_container() {
    log_step "${ICON_ROCKET} Запуск MTProto-прокси"

    cleanup_old

    local port_mapping
    port_mapping=$(compose_port_mapping)

    local engine_label="MTG v2 (Go)"
    local image_name="${MTG_IMAGE}"
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        engine_label="Telemt (Rust)"
        image_name="${TELEMT_IMAGE}"
    fi

    if [[ "$SNI_MODE" == true ]]; then
        log_info "Режим: ${BOLD}SNI-маршрутизация${RESET} (nginx stream → localhost:${MTG_INTERNAL_PORT})"
    else
        log_info "Режим: ${BOLD}Прямое подключение${RESET} (порт ${PROXY_PORT})"
    fi

    log_info "Параметры запуска:"
    log_sub "Движок:     ${BOLD}${engine_label}${RESET}"
    log_sub "Образ:      ${image_name}"
    log_sub "Контейнер:  ${CONTAINER_NAME}"
    log_sub "Порт:       ${port_mapping}"
    log_sub "FakeTLS:    ${FAKETLS_DOMAIN}"
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        log_sub "TCP Splice: включен (защита от Active Probing)"
        log_sub "ME Pool:    включен (быстрая загрузка медиа)"
    else
        log_sub "DNS:        ${DNS_RESOLVER}"
        log_sub "ulimit:     ${ULIMIT_NOFILE}"
    fi
    echo ""

    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        docker_run_telemt "${port_mapping}"
    else
        docker_run_mtg "${SECRET}" "${port_mapping}"
    fi

    log_ok "Контейнер запущен"
}

# ── Проверка здоровья ──
health_check() {
    log_step "${ICON_CLOCK} Проверка работоспособности"

    # Даём контейнеру 3 секунды на старт
    sleep 3

    local status
    status=$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "not_found")

    if [[ "$status" == "running" ]]; then
        log_ok "Контейнер работает ${ICON_CHECK}"
    else
        log_err "Контейнер НЕ запущен (статус: ${status})"
        log_info "Логи контейнера:"
        docker logs --tail 20 "${CONTAINER_NAME}" 2>&1 | while IFS= read -r line; do
            log_dim "$line"
        done
        exit 1
    fi

    # Подробная информация
    separator
    log_info "Подробная информация о контейнере:"

    local container_id uptime restart_count image_id
    container_id=$(docker inspect -f '{{.Id}}' "${CONTAINER_NAME}" | cut -c1-12)
    uptime=$(docker inspect -f '{{.State.StartedAt}}' "${CONTAINER_NAME}")
    restart_count=$(docker inspect -f '{{.RestartCount}}' "${CONTAINER_NAME}")
    image_id=$(docker inspect -f '{{.Image}}' "${CONTAINER_NAME}" | cut -c8-19)

    log_sub "Container ID:    ${BOLD}${container_id}${RESET}"
    log_sub "Engine:          ${BOLD}${PROXY_ENGINE}${RESET}"
    log_sub "Started at:      ${uptime}"
    log_sub "Restart count:   ${restart_count}"
    log_sub "Image hash:      ${image_id}"
    log_sub "Restart policy:  unless-stopped"
    log_sub "Port mapping:    ${PROXY_PORT} → 443"

    separator
    log_info "Последние логи:"
    docker logs --tail 10 "${CONTAINER_NAME}" 2>&1 | while IFS= read -r line; do
        log_dim "$line"
    done
}

# <<< END lib/docker.sh <<<

# >>> BEGIN lib/network.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/network.sh — Сетевой профиль: порт, stealth shaping, файрвол
# ══════════════════════════════════════════════════════════════════

# ── Проверка порта ──
check_port() {
    log_step "${ICON_SHIELD} Проверка порта ${PROXY_PORT}"

    if ss -tlnp | grep -q ":${PROXY_PORT} "; then
        local occupier process_name
        occupier=$(ss -tlnp | grep ":${PROXY_PORT} " | awk '{print $NF}')
        process_name=$(echo "$occupier" | grep -oP '"\K[^"]+' || echo "$occupier")

        # Если это наш контейнер — пересоздадим
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_info "Порт занят нашим контейнером ${CONTAINER_NAME}."
            log_info "Контейнер будет пересоздан."
            return 0
        fi

        # Определяем — это nginx или что-то другое?
        if echo "$process_name" | grep -qi "nginx"; then
            log_warn "Порт 443 занят ${BOLD}Nginx${RESET}"
            log_info "Включаю режим SNI-маршрутизации (nginx stream + ssl_preread)"
            log_dim "И сайты, и MTProto будут работать на одном порту 443"
            setup_nginx_sni_routing
            return 0
        fi

        # Не nginx — fallback на 8443
        log_warn "Порт ${BOLD}${PROXY_PORT}${RESET}${YELLOW} занят процессом: ${BOLD}${process_name}${RESET}"
        log_info "Переключаюсь на порт ${BOLD}${FALLBACK_PORT}${RESET}..."

        if ss -tlnp | grep -q ":${FALLBACK_PORT} "; then
            log_err "Порт ${FALLBACK_PORT} тоже занят. Освободите один из портов: 443 или ${FALLBACK_PORT}."
            exit 1
        fi

        PROXY_PORT="${FALLBACK_PORT}"
        log_ok "Порт ${PROXY_PORT} свободен, используем его"
        echo ""
        log_warn "${BOLD}Порт ${PROXY_PORT} — не стандартный HTTPS.${RESET}"
        log_dim "FakeTLS лучше всего маскирует трафик на порту 443."
        log_dim "На порту ${PROXY_PORT} DPI/ТСПУ теоретически может заподозрить TLS,"
        log_dim "но на практике для личного использования это работает нормально."
    else
        log_ok "Порт ${PROXY_PORT} свободен"
    fi
}

# ── Stealth-профиль (MSS + sysctl, БЕЗ netem) ──
apply_stealth_shaping() {
    log_step "${ICON_GEAR} Применение Stealth-профиля (MSS + BBR)"

    cat > "${SYSCTL_CONF}" << 'EOF'
fs.file-max = 2097152
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
EOF
    sysctl --system &>/dev/null

    local ETH_IF
    ETH_IF=$(detect_network_interface)

    log_info "Активный сетевой интерфейс: ${BOLD}${ETH_IF}${RESET}"

    # MSS Clamping (против DPI анализа размеров пакетов)
    iptables -t mangle -C POSTROUTING -p tcp --sport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850 2>/dev/null || \
    iptables -t mangle -A POSTROUTING -p tcp --sport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850

    iptables -t mangle -C PREROUTING -p tcp --dport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850 2>/dev/null || \
    iptables -t mangle -A PREROUTING -p tcp --dport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850

    # Удаляем tc netem если остался от старой версии (RTT fingerprint опасен)
    tc qdisc del dev "${ETH_IF}" root 2>/dev/null || true

    log_ok "Stealth: MSS=850 + BBR (netem удалён — RTT safe)"
}

# ── Настройка файрвола ──
configure_firewall() {
    log_step "${ICON_SHIELD} Настройка файрвола"

    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            log_info "UFW активен, открываю порт ${PROXY_PORT}/tcp..."
            ufw allow "${PROXY_PORT}/tcp" &>/dev/null
            log_ok "Порт ${PROXY_PORT}/tcp открыт в UFW"
        else
            log_dim "UFW установлен, но не активен. Пропускаю."
        fi
    else
        log_dim "UFW не установлен. Убедитесь, что порт ${PROXY_PORT} открыт в вашем файрволе."
    fi
}

# ── Очистка сетевых правил (для uninstall) ──
cleanup_network_rules() {
    log_step "${ICON_GEAR} Очистка сетевых правил"

    iptables -t mangle -D POSTROUTING -p tcp --sport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850 2>/dev/null || true
    iptables -t mangle -D PREROUTING -p tcp --dport "${PROXY_PORT}" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 850 2>/dev/null || true
    log_ok "Правила iptables MSS удалены"

    rm -f "${SYSCTL_CONF}"
    sysctl --system &>/dev/null
    log_ok "sysctl-профиль удалён"

    local ETH_IF
    ETH_IF=$(detect_network_interface)
    tc qdisc del dev "${ETH_IF}" root 2>/dev/null || true
}

# <<< END lib/network.sh <<<

# >>> BEGIN lib/nginx.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/nginx.sh — SNI-маршрутизация: stream, ssl_preread, backup, rollback
# Самый рискованный модуль — декомпозиция на 15 подфункций
# ══════════════════════════════════════════════════════════════════

# ── Переменная для хранения пути бекапа (mutable state) ──
NGINX_BACKUP_DIR=""

# ── Включение SNI-режима ──
enable_sni_mode() {
    SNI_MODE=true
    PROXY_PORT=443  # Внешний порт остаётся 443
}

# ── Проверка модуля stream ──
ensure_nginx_stream_module() {
    log_step "${ICON_GEAR} Проверка nginx модуля stream"

    if ! nginx -V 2>&1 | grep -q "with-stream"; then
        log_warn "Модуль stream не установлен. Устанавливаю..."
        if apt-get install -y -qq libnginx-mod-stream 2>/dev/null; then
            log_ok "Модуль stream установлен"
        else
            log_err "Не удалось установить модуль stream автоматически."
            log_sub "Установите вручную: ${BOLD}apt install libnginx-mod-stream${RESET}"
            exit 1
        fi
    fi
    log_ok "Модуль stream присутствует"
}

# ── Проверка ssl_preread ──
ensure_ssl_preread_support() {
    log_info "Проверка поддержки ssl_preread..."
    local test_conf="/etc/nginx/conf.d/_test_preread.conf.tmp"
    cat > "${test_conf}" <<PREREAD_TEST
stream {
    server {
        listen 127.0.0.1:65535;
        ssl_preread on;
        return "";
    }
}
PREREAD_TEST
    if ! nginx -t 2>/dev/null; then
        rm -f "${test_conf}"
        log_err "Модуль ssl_preread не доступен. SNI-маршрутизация невозможна."
        log_sub "Установите: ${BOLD}apt install libnginx-mod-stream${RESET} (с ssl_preread)"
        exit 1
    fi
    rm -f "${test_conf}"
    log_ok "ssl_preread поддерживается"
}

# ── Бекап nginx ──
backup_nginx_config() {
    log_step "${ICON_SHIELD} Бекап конфигурации Nginx"

    NGINX_BACKUP_DIR="/etc/nginx_backup_$(date +%s)"
    cp -r /etc/nginx "${NGINX_BACKUP_DIR}"
    log_ok "Бекап создан: ${BOLD}${NGINX_BACKUP_DIR}${RESET}"
}

# ── Автоматический поиск доменов из nginx конфигов ──
# ВАЖНО: результат в глобальной переменной _DISCOVERED_DOMAINS (не echo!)
# Причина: log_* пишут в stdout, а $() захватывает stdout → мусор в результате
_DISCOVERED_DOMAINS=""
discover_https_domains() {
    log_step "${ICON_INFO} Поиск доменов в конфигах Nginx"

    local user_domains

    # Метод 1: Собираем server_name ТОЛЬКО из файлов, где есть "listen 443 ssl"
    user_domains=$(grep -Rl "listen.*443.*ssl" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null \
        | xargs -r grep -Eho "server_name\s+[^;]+" \
        | awk '{for(i=2;i<=NF;i++) print $i}' \
        | grep -vE '^(_|localhost|""|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$' \
        | grep -v '^$' | sort -u | xargs || true)

    # Метод 2: Фоллбек через nginx -T
    if [[ -z "$user_domains" ]]; then
        log_info "Стандартные пути пусты, пробую nginx -T..."
        user_domains=$(nginx -T 2>/dev/null \
            | grep -E '^\s*server_name\s' \
            | grep -v '^\s*#' \
            | sed -E 's/server_name//g; s/;//g; s/#.*//g' \
            | tr ' ' '\n' | grep -v -E '^(_|localhost|"")$' | grep -v '^$' | sort -u | xargs || true)
    fi

    if [[ -z "$user_domains" ]]; then
        log_warn "Не удалось автоматически найти домены сайтов."
        echo -ne "  ${CYAN}Введите домены вручную (через пробел):${RESET} "
        read -r user_domains
        if [[ -z "$user_domains" ]]; then
            log_err "Домены не указаны. Остановка."
            exit 1
        fi
    else
        log_ok "Найдены домены: ${BOLD}${user_domains}${RESET}"
    fi

    _DISCOVERED_DOMAINS="$user_domains"
}

# ── Построение map entries для stream конфига ──
build_stream_map_entries() {
    local user_domains="$1"
    local map_entries=""

    for domain in $user_domains; do
        # Пропускаем FakeTLS домен — он уже маппится на mtproto_backend
        [[ "$domain" == "$FAKETLS_DOMAIN" ]] && continue
        map_entries+="        ${domain}    web_backend_intermediate;\n"
    done

    echo "$map_entries"
}

# ── Запись stream-конфига ──
write_stream_config() {
    local map_entries="$1"
    local intermediate_port=8444

    log_step "${ICON_GEAR} Генерация SNI-маршрутизатора"

    cat > "${STREAM_CONF}" << STREAMEOF
# ─────────────────────────────────────────────────────────────────
# SNI-маршрутизатор: Nginx + MTProto на порту 443
# Сгенерировано deploy_mt.sh $(date '+%Y-%m-%d %H:%M:%S')
# ─────────────────────────────────────────────────────────────────
stream {
    resolver 8.8.8.8 1.1.1.1 valid=300s;

    map \$ssl_preread_server_name \$backend {
        # 1. Если пришел пакет конкретно с нашим FAKETLS доменом -> кидаем в Телегу
        ${FAKETLS_DOMAIN}    mtproto_backend;
        
        # 2. Если пришел пакет с доменом вашего сайта -> на ваш сайт (если он есть)
$(echo -e "$map_entries")
        
        # 3. ВСЁ ОСТАЛЬНОЕ (сканеры РКН без SNI, левые домены) -> кидаем на Cloudflare
        default              external_fallback;
    }

    upstream mtproto_backend {
        server 127.0.0.1:${MTG_INTERNAL_PORT};
    }

    upstream web_backend_intermediate {
        server 127.0.0.1:${intermediate_port};
    }

    upstream external_fallback {
        # Прозрачно прокидываем сканеры на белый сайт
        server ${EXTERNAL_FALLBACK};
    }

    # Основной слушатель на внешнем 443
    server {
        listen 443;
        listen [::]:443;
        ssl_preread on;
        proxy_pass \$backend;
        
        # Против 16KB freeze + защита от обрывов
        proxy_buffer_size 16k;
        proxy_connect_timeout 10s;
        proxy_timeout 24h;
        tcp_nodelay on;
    }

    # Промежуточный сервер: добавляет proxy_protocol ТОЛЬКО для сайтов
    server {
        listen 127.0.0.1:${intermediate_port};
        proxy_pass 127.0.0.1:${NGINX_SITE_PORT};
        proxy_protocol on;
    }
}
STREAMEOF

    log_ok "Конфиг создан: ${BOLD}${STREAM_CONF}${RESET}"
    log_dim "Схема: :443 → SNI-роутер → сайты (через ${intermediate_port} с proxy_protocol)"
    log_dim "                          → MTProto (чистый TCP на ${MTG_INTERNAL_PORT})"
}

# ── Подключение stream-конфига к nginx.conf ──
ensure_stream_include() {
    log_step "${ICON_GEAR} Подключение stream-конфига к Nginx"

    local nginx_conf="/etc/nginx/nginx.conf"

    if grep -q "stream_mtproxy.conf" "${nginx_conf}"; then
        log_ok "Include уже есть в nginx.conf"
    else
        if grep -q "^http {" "${nginx_conf}" || grep -q "^http{" "${nginx_conf}"; then
            sed -i '/^http\s*{/i include /etc/nginx/stream_mtproxy.conf;' "${nginx_conf}"
            log_ok "Include добавлен в ${BOLD}${nginx_conf}${RESET} (перед http {})"
        else
            sed -i '1,/^[^#]/{/^[^#]/i include /etc/nginx/stream_mtproxy.conf; }' "${nginx_conf}"
            log_ok "Include добавлен в начало ${BOLD}${nginx_conf}${RESET}"
        fi
    fi
}

# ── Запись конфига для восстановления реальных IP ──
write_realip_conf() {
    cat > "${REALIP_CONF}" << 'REALIPEOF'
# Восстановление реальных IP от SNI-маршрутизатора (proxy_protocol)
# Сгенерировано deploy_mt.sh — НЕ УДАЛЯТЬ при использовании SNI-режима
set_real_ip_from 127.0.0.1;
real_ip_header proxy_protocol;
REALIPEOF
    log_ok "Создан ${BOLD}${REALIP_CONF}${RESET}"
}

# ── Поиск конфигов сайтов с listen 443 ──
# ВАЖНО: результат в глобальной переменной _FOUND_SITE_CONFIGS
_FOUND_SITE_CONFIGS=""
find_https_site_configs() {
    local conf_files

    # Метод 1: Прямой поиск в стандартных путях
    conf_files=$(grep -rlE "listen\s+(\[::\]:)?443" /etc/nginx/sites-available/ /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null \
        | grep -v "99-mtproto-realip" | grep -v "stream_mtproxy" | sort -u || true)

    # Метод 2: Фоллбек через nginx -T
    if [[ -z "$conf_files" ]]; then
        log_info "Стандартные пути не содержат listen 443, ищу через nginx -T..."
        conf_files=$(nginx -T 2>/dev/null \
            | grep -E '^# configuration file' \
            | sed 's/# configuration file //; s/:$//' \
            | while read -r f; do
                grep -lE "listen\s+(\[::\]:)?443" "$f" 2>/dev/null || true
            done | grep -v "99-mtproto-realip" | grep -v "stream_mtproxy" | grep -v "nginx.conf$" | sort -u || true)
    fi

    _FOUND_SITE_CONFIGS="$conf_files"
}

# ── Патч конфигов сайтов под intermediate port ──
patch_https_site_configs() {
    local conf_files="$1"

    log_step "${ICON_ROCKET} Автоматическое изменение конфигов сайтов"

    write_realip_conf

    if [[ -n "$conf_files" ]]; then
        for conf in $conf_files; do
            # IPv4: listen 443 ssl ... → listen 127.0.0.1:8443 ssl ... proxy_protocol;
            sed -i -E '/^\s*#/! { /proxy_protocol/! s/(listen\s+)443([^;]*);/\1127.0.0.1:'"${NGINX_SITE_PORT}"'\2 proxy_protocol;/g }' "$conf"
            # IPv6: listen [::]:443 ssl ... → listen [::1]:8443 ssl ... proxy_protocol;
            sed -i -E '/^\s*#/! { /proxy_protocol/! s/(listen\s+)\[::\]:443([^;]*);/\1[::1]:'"${NGINX_SITE_PORT}"'\2 proxy_protocol;/g }' "$conf"
            log_sub "Пропатчен: ${BOLD}$(basename "$conf")${RESET} (${conf})"
        done
        log_ok "Сайты переведены на 127.0.0.1:${NGINX_SITE_PORT} с proxy_protocol"
    else
        log_warn "Конфиги сайтов с listen 443 не найдены, патчить нечего."
    fi
}

# ── Откат nginx из бекапа ──
rollback_nginx_from_backup() {
    local reason="${1:-Ошибка конфигурации Nginx}"

    log_err "$reason"
    log_info "Откатываю ВСЕ изменения из бекапа..."

    if [[ -n "${NGINX_BACKUP_DIR}" && -d "${NGINX_BACKUP_DIR}" ]]; then
        rm -rf /etc/nginx
        cp -r "${NGINX_BACKUP_DIR}" /etc/nginx
    fi

    rm -f "${STREAM_CONF}"
    rm -f "${REALIP_CONF}"

    if nginx -t > /dev/null 2>&1; then
        systemctl restart nginx 2>/dev/null || true
        log_ok "Бекап восстановлен. Сервер работает как раньше."
    fi

    log_warn "Автоматика не справилась с вашими конфигами."
    log_sub "Бекап: ${BOLD}${NGINX_BACKUP_DIR}${RESET}"
    exit 1
}

# ── Проверка конфига nginx и рестарт (с откатом при ошибке) ──
validate_nginx_or_rollback() {
    log_info "Проверяю конфиг Nginx..."
    if ! nginx -t; then
        rollback_nginx_from_backup "Автоматический патч привел к ошибке конфига Nginx!"
    fi
    log_ok "Конфиг Nginx валиден"
}

restart_nginx_or_rollback() {
    log_info "Останавливаю Nginx..."
    systemctl stop nginx 2>/dev/null || true

    log_info "Запускаю Nginx с SNI-маршрутизацией..."
    if ! systemctl start nginx 2>/dev/null; then
        rollback_nginx_from_backup "Nginx не удалось запустить! Возможен конфликт портов."
    fi
    log_ok "Nginx перезапущен с SNI-маршрутизацией"
}

# ── Безопасное удаление SNI-артефактов (для uninstall) ──
uninstall_sni_artifacts_safe() {
    log_step "${ICON_SHIELD} Восстановление конфигурации Nginx"

    # Ищем последний бекап
    local latest_backup
    latest_backup=$(ls -dt /etc/nginx_backup_* 2>/dev/null | head -1)

    if [[ -n "$latest_backup" ]]; then
        rm -rf /etc/nginx
        cp -r "${latest_backup}" /etc/nginx
        rm -f "${STREAM_CONF}"
        rm -f "${REALIP_CONF}"

        if nginx -t > /dev/null 2>&1; then
            systemctl restart nginx
            log_ok "Nginx восстановлен из бекапа ${BOLD}${latest_backup}${RESET}"
        else
            log_err "Бекап повреждён! Проверьте nginx вручную."
        fi
    else
        # Нет бекапа — просто убираем наши файлы
        rm -f "${STREAM_CONF}"
        rm -f "${REALIP_CONF}"

        # Убираем include из nginx.conf
        sed -i '/stream_mtproxy.conf/d' /etc/nginx/nginx.conf 2>/dev/null

        log_warn "Бекап не найден. Убраны файлы SNI-маршрутизации."
        log_sub "Проверьте конфиги сайтов — listen порт мог остаться на 8443."
    fi
}

# ══════════════════════════════════════════════════════════════════
# ГЛАВНЫЙ ОРКЕСТРАТОР SNI-РЕЖИМА
# Вызывает все подфункции в правильном порядке
# ══════════════════════════════════════════════════════════════════
setup_nginx_sni_routing() {
    enable_sni_mode
    ensure_nginx_stream_module
    ensure_ssl_preread_support
    backup_nginx_config

    discover_https_domains
    local user_domains="$_DISCOVERED_DOMAINS"

    local map_entries
    map_entries=$(build_stream_map_entries "$user_domains")

    write_stream_config "$map_entries"
    ensure_stream_include

    find_https_site_configs
    patch_https_site_configs "$_FOUND_SITE_CONFIGS"

    validate_nginx_or_rollback
    restart_nginx_or_rollback
}

# <<< END lib/nginx.sh <<<

# >>> BEGIN lib/actions.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/actions.sh — Высокоуровневые пользовательские действия
# check_existing, show_status, uninstall_all, migrate, engine select
# ══════════════════════════════════════════════════════════════════

# ── Выбор движка при свежей установке ──
select_engine() {
    echo ""
    echo -e "  ${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${CYAN}${BOLD}║          Выберите движок MTProto-прокси                  ║${RESET}"
    echo -e "  ${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${GREEN}1${RESET}) ${BOLD}Telemt (Rust)${RESET}  — ${GREEN}РЕКОМЕНДУЕТСЯ${RESET}"
    echo -e "     ${DIM}TCP Splicing, быстрая загрузка медиа, TLS-эмуляция${RESET}"
    echo ""
    echo -e "  ${CYAN}2${RESET}) ${BOLD}MTG v2 (Go)${RESET}    — Legacy"
    echo -e "     ${DIM}Классический движок, проверенный временем${RESET}"
    echo ""
    echo -ne "  ${CYAN}Выбор [1-2] (по умолчанию 1):${RESET} "
    read -r engine_choice

    case "${engine_choice:-1}" in
        1)
            PROXY_ENGINE="telemt"
            log_ok "Выбран движок: ${BOLD}Telemt (Rust)${RESET}"
            ;;
        2)
            PROXY_ENGINE="mtg"
            log_ok "Выбран движок: ${BOLD}MTG v2 (Go)${RESET}"
            ;;
        *)
            PROXY_ENGINE="telemt"
            log_ok "Выбран движок по умолчанию: ${BOLD}Telemt (Rust)${RESET}"
            ;;
    esac
}

# ── Проверка существующей установки ──
check_existing() {
    # Нет конфига — свежая установка
    if ! config_exists; then
        return 1
    fi

    # Загружаем сохранённый конфиг (safe-loader, без source)
    load_config_safe

    # Проверяем контейнер
    local status
    status=$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "not_found")

    echo ""
    echo -e "  ${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${YELLOW}${BOLD}║   Обнаружена существующая установка MTProto-прокси!      ║${RESET}"
    echo -e "  ${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}Сервер:${RESET}     ${BOLD}${SERVER_IP}${RESET}"
    echo -e "  ${CYAN}Порт:${RESET}       ${BOLD}${PROXY_PORT}${RESET}"
    echo -e "  ${CYAN}Контейнер:${RESET}  ${BOLD}${CONTAINER_NAME}${RESET} — ${status}"
    echo -e "  ${CYAN}Движок:${RESET}     ${BOLD}${PROXY_ENGINE:-mtg}${RESET}"
    echo -e "  ${CYAN}SNI-режим:${RESET}  ${BOLD}${SNI_MODE:-false}${RESET}"
    echo -e "  ${CYAN}FakeTLS:${RESET}    ${BOLD}${FAKETLS_DOMAIN}${RESET}"
    echo ""
    separator
    echo ""
    echo -e "  ${WHITE}${BOLD}Что сделать?${RESET}"
    echo ""
    echo -e "  ${CYAN}1${RESET}) ${BOLD}Обновить образ${RESET}  — pull новый образ, пересоздать контейнер (секрет сохранится)"
    if [[ "${PROXY_ENGINE:-mtg}" == "mtg" ]]; then
        echo -e "  ${GREEN}2${RESET}) ${BOLD}⚡ Мигрировать на Telemt${RESET} — переход на Rust-движок (ссылки обновятся)"
    fi
    echo -e "  ${CYAN}3${RESET}) ${BOLD}Переустановить${RESET} — полная переустановка с нуля (новый секрет)"
    echo -e "  ${CYAN}4${RESET}) ${BOLD}Удалить всё${RESET}    — убрать прокси и вернуть nginx как было"
    echo -e "  ${CYAN}5${RESET}) ${BOLD}Статус${RESET}         — показать ссылки подключения и логи"
    echo -e "  ${CYAN}6${RESET}) ${BOLD}Выход${RESET}"
    echo ""
    echo -ne "  ${CYAN}Выбор [1-6]:${RESET} "
    read -r choice

    case "$choice" in
        1)
            update_flow
            exit 0
            ;;
        2)
            if [[ "${PROXY_ENGINE:-mtg}" == "mtg" ]]; then
                migrate_to_telemt
                exit 0
            else
                log_err "Неверный выбор."
                exit 1
            fi
            ;;
        3)
            reinstall_flow
            return 1  # Продолжить как свежая установка
            ;;
        4)
            uninstall_all
            exit 0
            ;;
        5)
            show_status
            exit 0
            ;;
        6)
            log_info "Выход."
            exit 0
            ;;
        *)
            log_err "Неверный выбор."
            exit 1
            ;;
    esac
}

# ── Обновление образа ──
update_flow() {
    local image_to_pull="${MTG_IMAGE}"
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        image_to_pull="${TELEMT_IMAGE}"
    fi

    log_step "${ICON_ROCKET} Обновление образа (${PROXY_ENGINE})"
    docker pull "${image_to_pull}" 2>&1 | tail -3
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        generate_telemt_config
    fi

    launch_container
    health_check
    save_config
    log_ok "Образ обновлён, контейнер пересоздан"
    print_connection_info
}

# ── Миграция с MTG v2 на Telemt ──
migrate_to_telemt() {
    log_step "${ICON_ROCKET} Миграция MTG v2 → Telemt (Rust)"

    echo ""
    echo -e "  ${YELLOW}${BOLD}Что произойдёт:${RESET}"
    echo -e "    ${WHITE}1. Старый контейнер mtg будет остановлен${RESET}"
    echo -e "    ${WHITE}2. Сгенерируется новый секрет (формат Telemt: 32-hex)${RESET}"
    echo -e "    ${WHITE}3. Запустится контейнер Telemt (Rust)${RESET}"
    echo -e "    ${WHITE}4. ${BOLD}Ссылки изменятся${RESET}${WHITE} — нужно будет обновить на устройствах${RESET}"
    echo ""
    echo -ne "  ${CYAN}Продолжить? [y/N]:${RESET} "
    read -r confirm
    if [[ "${confirm,,}" != "y" && "${confirm,,}" != "д" ]]; then
        log_info "Миграция отменена."
        return 0
    fi

    # 1. Генерируем новый секрет
    PROXY_ENGINE="telemt"
    generate_secret_telemt

    # 2. Генерируем config.toml
    generate_telemt_config

    # 3. Пересоздаём контейнер
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    launch_container
    health_check

    # 4. Сохраняем конфиг с новым ENGINE
    save_config
    install_rotate_script

    log_ok "Миграция завершена! Движок: ${BOLD}Telemt (Rust)${RESET}"
    print_connection_info
}

# ── Переустановка ──
reinstall_flow() {
    log_info "Удаляю старую установку перед переустановкой..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    rm -f "$CONFIG_FILE"
    # НЕ трогаем nginx — он будет перенастроен заново
}

# ── Показать статус и ссылки ──
show_status() {
    load_config_safe

    local status
    status=$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "not_found")

    log_step "${ICON_INFO} Статус MTProto-прокси"

    if [[ "$status" == "running" ]]; then
        log_ok "Контейнер ${BOLD}${CONTAINER_NAME}${RESET} работает ${ICON_CHECK}"
    else
        log_err "Контейнер ${BOLD}${CONTAINER_NAME}${RESET} НЕ запущен (статус: ${status})"
    fi

    echo ""
    print_connection_info

    log_step "${ICON_GEAR} Последние логи"
    docker logs --tail 15 "${CONTAINER_NAME}" 2>&1 | while IFS= read -r line; do
        log_sub "$line"
    done
}

# ── Полное удаление ──
uninstall_all() {
    log_step "${ICON_WARN} Удаление MTProto-прокси"

    # 1. Удаляем контейнер
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker rm -f "${CONTAINER_NAME}" 2>/dev/null
        log_ok "Контейнер ${BOLD}${CONTAINER_NAME}${RESET} удалён"
    else
        log_dim "Контейнер не найден, пропускаю."
    fi

    # 2. Восстанавливаем nginx из бекапа (если SNI-режим)
    if [[ "${SNI_MODE}" == true ]]; then
        uninstall_sni_artifacts_safe
    fi

    # 3. Удаляем конфиг
    rm -f "$CONFIG_FILE"
    log_ok "Конфигурация удалена"

    # 4. Очистка сетевых правил
    cleanup_network_rules

    # 5. Удаляем скрипт ротации
    rm -f "${ROTATE_SCRIPT}"
    log_ok "Скрипт ротации удалён"

    echo ""
    echo -e "  ${GREEN}${BOLD}✅ MTProto-прокси полностью удалён.${RESET}"
    echo -e "  ${WHITE}Сервер вернулся в исходное состояние.${RESET}"
    echo ""
}

# ── Установка rotate-скрипта (копирование файла вместо heredoc) ──
install_rotate_script() {
    # Определяем директорию скрипта (для build-режима — рядом с deploy_mt.sh)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # В собранном single-file rotate_fallback.sh встроен как heredoc ниже
    # В модульном режиме — копируем из репозитория
    # Генерируем rotate_fallback.sh с правильными путями
    cat > "${ROTATE_SCRIPT}" << 'ROTATE_EOF'
#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# rotate_fallback.sh — Ротация FakeTLS домена MTProto
# Запуск: sudo bash /root/rotate_fallback.sh (вручную, при блокировке)
# ВНИМАНИЕ: после ротации нужно обновить ссылки на всех устройствах!
# ─────────────────────────────────────────────────────────────────

CONFIG="/root/.mtproto-proxy.conf"
[[ ! -f "$CONFIG" ]] && echo "Конфиг не найден" && exit 1

# Safe config loader (без source)
while IFS='=' read -r k v; do
    v="${v%\"}"
    v="${v#\"}"
    case "$k" in
        SERVER_IP|PROXY_PORT|FAKETLS_DOMAIN|SECRET|CONTAINER_NAME|MTG_IMAGE|SNI_MODE|MTG_INTERNAL_PORT|STREAM_CONF)
            printf -v "$k" '%s' "$v"
            ;;
    esac
done < <(grep -E '^(SERVER_IP|PROXY_PORT|FAKETLS_DOMAIN|SECRET|CONTAINER_NAME|MTG_IMAGE|SNI_MODE|MTG_INTERNAL_PORT|STREAM_CONF)=' "$CONFIG")

# В SNI-режиме ротация сломает nginx stream config (рассинхрон домена)
if [[ "${SNI_MODE:-false}" == "true" ]]; then
    echo "ОШИБКА: ротация не поддерживается при SNI_MODE=true"
    echo "В SNI-режиме домен прошит в ${STREAM_CONF:-/etc/nginx/stream_mtproxy.conf}"
    echo "Для ротации: переустановите прокси через deploy_mt.sh (опция 2)"
    exit 1
fi

RF_DOMAINS=("yandex.ru" "mail.ru" "ok.ru" "sberbank.ru" "beeline.ru" "rambler.ru" "rutube.ru")

# Выбираем новый домен (отличный от текущего)
NEW_DOMAIN="${FAKETLS_DOMAIN}"
while [[ "$NEW_DOMAIN" == "${FAKETLS_DOMAIN}" ]]; do
    NEW_DOMAIN="${RF_DOMAINS[$RANDOM % ${#RF_DOMAINS[@]}]}"
done

# Генерируем новый секрет
NEW_SECRET=$(docker run --rm "${MTG_IMAGE}" generate-secret "$NEW_DOMAIN" 2>/dev/null | tail -1 || true)

if [[ -z "$NEW_SECRET" || ${#NEW_SECRET} -lt 32 ]]; then
    echo "ОШИБКА: Не удалось сгенерировать секрет для домена ${NEW_DOMAIN}"
    exit 1
fi

# Пересоздаём контейнер
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

# Определяем порт-маппинг
if [[ "${SNI_MODE}" == "true" ]]; then
    PORT_MAP="127.0.0.1:${MTG_INTERNAL_PORT}:443"
else
    PORT_MAP="${PROXY_PORT}:443"
fi

docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=16m \
    --security-opt no-new-privileges \
    --pids-limit 1024 \
    --memory 256m \
    --cpus 0.75 \
    --ulimit nofile=51200:51200 \
    -p "${PORT_MAP}" \
    "${MTG_IMAGE}" \
    simple-run -n 1.1.1.1 -i prefer-ipv4 "0.0.0.0:443" "${NEW_SECRET}"

# Обновляем конфиг
sed -i "s/^FAKETLS_DOMAIN=.*/FAKETLS_DOMAIN=${NEW_DOMAIN}/" "$CONFIG"
sed -i "s/^SECRET=.*/SECRET=${NEW_SECRET}/" "$CONFIG"

echo "$(date '+%Y-%m-%d %H:%M:%S') [ROTATE] ${FAKETLS_DOMAIN} → ${NEW_DOMAIN} | Secret: ${NEW_SECRET:0:16}..."
ROTATE_EOF

    chmod +x "${ROTATE_SCRIPT}"
    log_ok "Скрипт ротации создан: ${BOLD}${ROTATE_SCRIPT}${RESET}"

    if [[ "${SNI_MODE}" == "true" ]]; then
        log_warn "В SNI-режиме ротация заблокирована (рассинхрон с nginx)"
        log_dim "Для смены домена: переустановите через ${BOLD}deploy_mt.sh${RESET} (опция 2)"
    else
        log_dim "Запускайте вручную при блокировке: ${BOLD}bash ${ROTATE_SCRIPT}${RESET}"
        log_dim "После ротации потребуется обновить ссылки на всех устройствах"
    fi
}

# <<< END lib/actions.sh <<<

# >>> BEGIN lib/output.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/output.sh — Presentation и UX: banner, ссылки подключения
# ══════════════════════════════════════════════════════════════════

# ── ASCII-баннер ──
show_banner() {
cat << 'BANNER'

BANNER
echo -e "${CYAN}${BOLD}"
cat << 'ASCII'
    ╔═══════════════════════════════════════════════════════════════════╗
    ║                                                                   ║
    ║   ███╗   ███╗████████╗██████╗ ██████╗  ██████╗ ████████╗ ██████╗  ║
    ║   ████╗ ████║╚══██╔══╝██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔═══██╗ ║
    ║   ██╔████╔██║   ██║   ██████╔╝██████╔╝██║   ██║   ██║   ██║   ██║ ║
    ║   ██║╚██╔╝██║   ██║   ██╔═══╝ ██╔══██╗██║   ██║   ██║   ██║   ██║ ║
    ║   ██║ ╚═╝ ██║   ██║   ██║     ██║  ██║╚██████╔╝   ██║   ╚██████╔╝ ║
    ║   ╚═╝     ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ║
    ║                                                                   ║
    ║                    ███╗   ██╗███████╗██╗  ██╗                     ║
    ║                    ████╗  ██║╚══███╔╝██║ ██╔╝                     ║
    ║                    ██╔██╗ ██║  ███╔╝ █████╔╝                      ║
    ║                    ██║╚██╗██║ ███╔╝  ██╔═██╗                      ║
    ║                    ██║ ╚████║███████╗██║  ██╗                     ║
    ║                    ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝                     ║
    ║                                                                   ║
    ╚═══════════════════════════════════════════════════════════════════╝
ASCII
echo -e "${RESET}"
echo -e "${WHITE}${BOLD}       ⚡ Telegram MTProto FakeTLS Proxy Deployer ⚡${RESET}"
echo -e "${CYAN}          ${PROXY_ENGINE:-mtg}  ·  Docker  ·  Fake TLS 1.3${RESET}"
echo -e "${WHITE}          $(date '+%Y-%m-%d   %H:%M:%S %Z')${RESET}"
echo ""
separator
}

# ── Вывод инструкции подключения ──
print_connection_info() {
    # Для FakeTLS ссылок нужен формат: ee + secret + hex(domain)
    local link_secret="${SECRET}"
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        local hex_domain
        hex_domain=$(printf '%s' "${FAKETLS_DOMAIN}" | xxd -p -c 256)
        link_secret="ee${SECRET}${hex_domain}"
    fi

    local tg_link="tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${link_secret}"
    local https_link="https://t.me/proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${link_secret}"

    echo ""
    echo ""
    echo -e "${GREEN}${BOLD}"
    cat << 'SUCCESS'
    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║        ✅  ПРОКСИ УСПЕШНО РАЗВЁРНУТ И РАБОТАЕТ!  ✅      ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
SUCCESS
    echo -e "${RESET}"

    echo -e "  ${YELLOW}${BOLD}📝 Полезные команды:${RESET}"
    echo ""
    echo -e "    ${WHITE}Статус контейнера:${RESET}   docker ps -f name=${CONTAINER_NAME}"
    echo -e "    ${WHITE}Логи (live):${RESET}         docker logs -f ${CONTAINER_NAME}"
    echo -e "    ${WHITE}Перезапуск:${RESET}          docker restart ${CONTAINER_NAME}"
    echo -e "    ${WHITE}Остановить:${RESET}          docker stop ${CONTAINER_NAME}"
    echo -e "    ${WHITE}Удалить:${RESET}             docker rm -f ${CONTAINER_NAME}"
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        echo -e "    ${WHITE}Обновить:${RESET}            docker pull ${TELEMT_IMAGE} && docker rm -f ${CONTAINER_NAME} && sudo ./deploy_mt.sh"
    else
        echo -e "    ${WHITE}Обновить:${RESET}            docker pull ${MTG_IMAGE} && docker rm -f ${CONTAINER_NAME} && sudo ./deploy_mt.sh"
    fi
    echo ""
    separator
    echo ""
    echo -e "  ${MAGENTA}${BOLD}${ICON_SHIELD} Безопасность:${RESET}"
    echo -e "    ${WHITE}• Трафик маскируется под TLS 1.3 к ${FAKETLS_DOMAIN}${RESET}"
    if [[ "$SNI_MODE" == true ]]; then
        echo -e "    ${WHITE}• ${BOLD}SNI-режим:${RESET}${WHITE} nginx stream мультиплексирует порт 443${RESET}"
        echo -e "    ${WHITE}• Сайты и MTProto работают на одном порту — внешне не различимы${RESET}"
        echo -e "    ${WHITE}• MTProto слушает только localhost:${MTG_INTERNAL_PORT} (недоступен снаружи)${RESET}"
        echo -e "    ${WHITE}• Stream-конфиг: ${STREAM_CONF}${RESET}"
    else
        echo -e "    ${WHITE}• Порт ${PROXY_PORT} выглядит как стандартный HTTPS${RESET}"
    fi
    echo -e "    ${WHITE}• При открытии IP в браузере — пустая страница (нет следов MTProto)${RESET}"
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        echo -e "    ${WHITE}• ${BOLD}TCP Splicing:${RESET}${WHITE} при сканировании возвращается реальный сайт${RESET}"
        echo -e "    ${WHITE}• ${BOLD}ME Pool:${RESET}${WHITE} быстрая загрузка фото/видео в Telegram${RESET}"
    fi
    echo -e "    ${WHITE}• Конфигурация сохранена в ${CONFIG_FILE}${RESET}"
    echo ""
    if [[ "$SNI_MODE" == true ]]; then
        echo -e "  ${YELLOW}${BOLD}🔧 SNI-специфичные команды:${RESET}"
        echo -e "    ${WHITE}Конфиг маршрутизатора:${RESET}  cat ${STREAM_CONF}"
        echo -e "    ${WHITE}Бекап nginx:${RESET}           ls /etc/nginx_backup_*"
        echo -e "    ${WHITE}Перезапуск nginx:${RESET}      systemctl restart nginx"
        echo ""
    fi
    separator
    echo ""
    echo -e "${CYAN}${BOLD}  📱 КАК ПОДКЛЮЧИТЬ TELEGRAM:${RESET}"
    separator
    echo ""
    echo -e "  ${WHITE}${BOLD}Способ 1 — Ссылка tg:// (рекомендуется)${RESET}"
    echo -e "  ${WHITE}Откройте эту ссылку на устройстве с Telegram:${RESET}"
    echo ""
    echo -e "  ${GREEN}${BOLD}${tg_link}${RESET}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Способ 2 — Веб-ссылка t.me${RESET}"
    echo -e "  ${WHITE}Откройте в любом браузере:${RESET}"
    echo ""
    echo -e "  ${GREEN}${BOLD}${https_link}${RESET}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Способ 3 — Ручная настройка${RESET}"
    echo -e "  ${WHITE}Telegram → Настройки → Данные и память → Прокси → Добавить прокси${RESET}"
    echo ""
    echo -e "    ${CYAN}Сервер:${RESET}  ${BOLD}${SERVER_IP}${RESET}"
    echo -e "    ${CYAN}Порт:${RESET}    ${BOLD}${PROXY_PORT}${RESET}"
    echo -e "    ${CYAN}Секрет:${RESET}  ${BOLD}${link_secret}${RESET}"
    echo ""
    local engine_label="mtg v2"
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        engine_label="Telemt (Rust)"
    fi
    echo -e "  ${CYAN}Deployed at $(date '+%Y-%m-%d %H:%M:%S %Z') | ${engine_label} FakeTLS${RESET}"
    echo ""
}

# <<< END lib/output.sh <<<

# >>> BEGIN lib/main.sh >>>
# ══════════════════════════════════════════════════════════════════
# lib/main.sh — Orchestration entrypoint
# Порядок шагов строго по оригинальному main()
# ══════════════════════════════════════════════════════════════════

main() {
    show_banner
    check_root

    # Проверка существующей установки
    if check_existing; then
        exit 0  # Действие выполнено внутри check_existing
    fi

    # Свежая установка
    detect_os
    check_dependencies
    ensure_docker
    detect_ip
    select_engine
    select_faketls_domain

    # Генерация секрета и конфига — зависит от движка
    if [[ "$PROXY_ENGINE" == "telemt" ]]; then
        generate_secret_telemt
        check_port
        generate_telemt_config
    else
        generate_secret
        check_port
    fi

    apply_stealth_shaping
    launch_container
    health_check
    configure_firewall
    save_config
    install_rotate_script
    print_connection_info
}

main "$@"

# <<< END lib/main.sh <<<
