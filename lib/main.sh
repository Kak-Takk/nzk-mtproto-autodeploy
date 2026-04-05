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
