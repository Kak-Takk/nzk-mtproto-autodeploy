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
