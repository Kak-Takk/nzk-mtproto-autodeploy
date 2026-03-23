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

    # Свежая установка — 18 шагов
    detect_os
    check_dependencies
    ensure_docker
    detect_ip
    select_faketls_domain
    generate_secret
    check_port
    apply_stealth_shaping
    launch_container
    health_check
    configure_firewall
    save_config
    install_rotate_script
    print_connection_info
}

main "$@"
