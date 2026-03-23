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
            if [[ ! " ${pkgs_to_install[*]} " =~ " ${pkg_name} " ]]; then
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
