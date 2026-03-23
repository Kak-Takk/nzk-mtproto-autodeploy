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
