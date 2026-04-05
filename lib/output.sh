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
