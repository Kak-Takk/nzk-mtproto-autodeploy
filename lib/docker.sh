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
