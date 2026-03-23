# ══════════════════════════════════════════════════════════════════
# lib/actions.sh — Высокоуровневые пользовательские действия
# check_existing, show_status, uninstall_all
# ══════════════════════════════════════════════════════════════════

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
    echo -e "  ${CYAN}SNI-режим:${RESET}  ${BOLD}${SNI_MODE:-false}${RESET}"
    echo -e "  ${CYAN}FakeTLS:${RESET}    ${BOLD}${FAKETLS_DOMAIN}${RESET}"
    echo ""
    separator
    echo ""
    echo -e "  ${WHITE}${BOLD}Что сделать?${RESET}"
    echo ""
    echo -e "  ${CYAN}1${RESET}) ${BOLD}Обновить образ${RESET}  — pull новый mtg, пересоздать контейнер (секрет сохранится)"
    echo -e "  ${CYAN}2${RESET}) ${BOLD}Переустановить${RESET} — полная переустановка с нуля (новый секрет)"
    echo -e "  ${CYAN}3${RESET}) ${BOLD}Удалить всё${RESET}    — убрать прокси и вернуть nginx как было"
    echo -e "  ${CYAN}4${RESET}) ${BOLD}Статус${RESET}         — показать ссылки подключения и логи"
    echo -e "  ${CYAN}5${RESET}) ${BOLD}Выход${RESET}"
    echo ""
    echo -ne "  ${CYAN}Выбор [1-5]:${RESET} "
    read -r choice

    case "$choice" in
        1)
            update_flow
            exit 0
            ;;
        2)
            reinstall_flow
            return 1  # Продолжить как свежая установка
            ;;
        3)
            uninstall_all
            exit 0
            ;;
        4)
            show_status
            exit 0
            ;;
        5)
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
    log_step "${ICON_ROCKET} Обновление образа MTProto"
    docker pull "${MTG_IMAGE}" 2>&1 | tail -3
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    launch_container
    health_check
    save_config
    log_ok "Образ обновлён, контейнер пересоздан"
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
set -euo pipefail

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
