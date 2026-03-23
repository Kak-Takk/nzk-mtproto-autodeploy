# ══════════════════════════════════════════════════════════════════
# lib/docker.sh — Docker-логика: secret, контейнер, health check
# ══════════════════════════════════════════════════════════════════

# ── Генерация FakeTLS секрета ──
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

    if [[ "$SNI_MODE" == true ]]; then
        log_info "Режим: ${BOLD}SNI-маршрутизация${RESET} (nginx stream → localhost:${MTG_INTERNAL_PORT})"
    else
        log_info "Режим: ${BOLD}Прямое подключение${RESET} (порт ${PROXY_PORT})"
    fi

    log_info "Параметры запуска:"
    log_sub "Образ:      ${MTG_IMAGE}"
    log_sub "Контейнер:  ${CONTAINER_NAME}"
    log_sub "Порт:       ${port_mapping}"
    log_sub "DNS:        ${DNS_RESOLVER}"
    log_sub "FakeTLS:    ${FAKETLS_DOMAIN}"
    log_sub "ulimit:     ${ULIMIT_NOFILE}"
    echo ""

    docker_run_mtg "${SECRET}" "${port_mapping}"

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
