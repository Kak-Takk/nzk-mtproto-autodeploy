# ══════════════════════════════════════════════════════════════════
# lib/config.sh — Конфигурация: safe-loader, save, validate, update
# ══════════════════════════════════════════════════════════════════

# Whitelist допустимых ключей конфига
readonly CONFIG_KEYS="SERVER_IP|PROXY_PORT|FAKETLS_DOMAIN|EXTERNAL_FALLBACK|SECRET|CONTAINER_NAME|MTG_IMAGE|SNI_MODE|MTG_INTERNAL_PORT|STREAM_CONF"

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
