<div align="center">

# 🛡️ MTProto FakeTLS Proxy Deployer
[English](README_EN.md) | **Русский**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash%205.0+-green.svg)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/Docker-Required-2496ED.svg?logo=docker)](https://www.docker.com/)
[![Telemt](https://img.shields.io/badge/Telemt-Rust-orange.svg)](https://github.com/telemt/telemt)
[![MTG](https://img.shields.io/badge/mtg-v2%20legacy-lightgrey.svg)](https://github.com/9seconds/mtg)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420.svg?logo=ubuntu)](https://ubuntu.com/)

<br>

<img src="banner.png" alt="NZK MTPROTO FakeTLS Proxy Deployer" width="800">

**Автоматический деплой MTProto-прокси с маскировкой под обычный сайт (FakeTLS + SNI)**

[Быстрый старт](#-быстрый-старт) • [Возможности](#-возможности) • [Архитектура](#архитектура) • [FAQ](#-faq)

---

</div>

## ⚡ Быстрый старт

```bash
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/main/deploy_mt.sh -o deploy_mt.sh && sudo bash deploy_mt.sh
```

> **Одна команда** — и через 30 секунд у вас готовый MTProto-прокси на порту 443 с FakeTLS маскировкой.

<details>
<summary><b>🔒 Audit-first установка (рекомендуется)</b></summary>

```bash
# 1. Скачать
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/main/deploy_mt.sh -o deploy_mt.sh

# 2. Прочитать код перед запуском
less deploy_mt.sh

# 3. Запустить
chmod +x deploy_mt.sh && sudo ./deploy_mt.sh
```

Или установка по конкретному тегу (воспроизводимость):
```bash
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/v0.2.0/deploy_mt.sh -o deploy_mt.sh
```
</details>

🔍 **Проверить качество маскировки (Smoke-Test):**

```bash
curl -sSL https://raw.githubusercontent.com/Kak-Takk/nzk-mtproto-autodeploy/main/smoke-mtproto.sh -o smoke-mtproto.sh && sudo bash smoke-mtproto.sh
```

---

## 🎯 Какие проблемы решает?

Системы глубокого анализа трафика (DPI) используют три основных вектора для блокировки прокси. Наш скрипт закрывает каждый:

| Вектор атаки | Что делает DPI | Наша защита |
|---|---|---|
| **Active Probing** | Сканирует порт 443, отправляя поддельные TLS ClientHello | **TCP Splicing (Telemt):** сканер получает реальный сайт, а не отпечаток прокси |
| **Passive Fingerprinting** | Анализ размеров пакетов, MSS, RTT-паттерны | MSS=850 + BBR + TLS-эмуляция (Telemt копирует реальные TLS-записи) |
| **Statistical Analysis** | Корреляция SNI с IP/ASN, долгоживущие сессии | RF-домены + ручная ротация при блокировке |

### 💡 Ключевой принцип

Обычные MTProto-установщики просто вешают прокси на открытый порт — DPI сканирует, видит аномалию, блокирует. Мы интегрируем прокси в веб-сервер через **Nginx SNI-роутинг**: сканеры получают TLS-ошибку или редирект, а MTProto-трафик уходит в контейнер.
Это значительно повышает стоимость детектирования. Не идеальный stealth (IP вашего VPS отличается от реального IP RF-домена), но практичный и эффективный для личного использования. Вдохновлено принципом **VLESS+Reality**.

---

## 🚀 Возможности

<table>
<tr>
<td width="50%">

### 🔧 Полная автоматизация
- Установка Docker (если нет)
- Установка `nginx stream` модуля
- Генерация FakeTLS секрета
- Запуск контейнера
- Настройка файрвола

</td>
<td width="50%">

### 🛡️ Продвинутая маскировка (Fallback)
- Защита от Active Probing сканирований
- Ваш реальный сайт работает как "щит" (Fallback)
- Сайты + MTProto на **одном 443 порту**
- `proxy_protocol` для сохранения реальных IP
- Автодетект и патч конфигов ваших сайтов

</td>
</tr>
<tr>
<td>

### 🛡️ Stealth-профиль (v2.0)
- **Умный FakeTLS:** Авто-подбор RF-доменов (`yandex.ru`, `mail.ru` и др.) для маскировки
- **TCP-оптимизация:** `BBR` + `TCPMSS=850` для естественного сетевого профиля (без палевного `tc netem`)
- **Защита от Timeout:** `proxy_buffer_size 16k` для обхода «заморозки» соединений
- **Ручная ротация:** Скрипт `/root/rotate_fallback.sh` — запускайте вручную при блокировке для смены домена и секрета

</td>
<td>

### 📦 Повторный запуск
- Детект существующей установки
- Обновление образа (секрет сохраняется)
- Полная переустановка
- Удаление с откатом Nginx

</td>
</tr>
<tr>
<td>

### 🔒 Docker Hardening
- `--read-only` контейнер (нет записи на диск)
- Лимиты: **256MB RAM**, 1024 PIDs, 0.75 CPU
- `--security-opt no-new-privileges`
- `tmpfs /tmp` вместо disk write
- `ulimit nofile 51200`

</td>
<td>

### 🔬 Встроенный Smoke-Test
- Полная диагностика: Docker, TLS SNI, iptables, sysctl
- Анализ трафика через `tcpdump` (MSS, размеры пакетов, jitter)
- Опциональный `tshark` анализ SNI в ClientHello
- Итоговый счётчик PASS / FAIL / WARN

</td>
</tr>
</table>

---

## 🧬 Technology DNA

Мы взяли лучшие техники из топовых инструментов сетевой безопасности и объединили в единое решение:

| Технология | Откуда взяли | Как применяем |
|---|---|---|
| **FakeTLS + реальный сертификат** | VLESS+Reality | mtg проксирует TLS до настоящего сервера — DPI видит настоящий сертификат |
| **SNI-роутинг (один порт)** | Cloak / Trojan-GFW | Nginx Stream мультиплексирует сайты + прокси на :443 |
| **MSS Clamping** | GoodbyeDPI / zapret | `iptables` обрезает MSS до 850 — DPI не видит серверную сигнатуру |
| **BBR + sysctl стек** | Enterprise CDN | Оптимизация ядра: FQ, BBR, tcp_notsent_lowat, keepalive |
| **Ротация профилей** | Outline / Shadowsocks | Ручной скрипт меняет домен + секрет при блокировке |
| **Container Hardening** | Docker CIS Benchmark | read-only, no-new-privileges, memory/PIDs limits |

---

<a id="архитектура"></a>

## 🏗️ Архитектура

### Режим 1 — Прямое подключение (порт свободен)

```text
+----------+         +------------------------+
| Telegram |---443-->|  MTProto Proxy          |
|  Client  |         |  (Telemt / mtg v2)      |
+----------+         +------------------------+
                     Сетевые фильтры видят: TLS 1.3 -> mail.ru (TCP Splicing — реальный сайт)
```

### Режим 2 — SNI-маршрутизация (Nginx на 443)

```text
                               +------------------+
                      +--SNI-->|  Ваши сайты      |
+----------+          | match  |  :8443 + PP      |
|  Клиент  |---443--->|        +------------------+
|          |          | Nginx
+----------+          | Stream +------------------+
                      | FTLS-->|  MTProto Proxy   |
                      | домен  |  :1443 (чистый)  |
                      |        +------------------+
                      |        +------------------+
                      +default>|  Внешний сайт    |
                       (SNI)   |  (fallback)      |
                               +------------------+

DPI видит: обычный HTTPS-трафик на 443
Ваши сайты: работают как раньше, IP клиентов сохраняются
MTProto: маршрутизируется по SNI FakeTLS-домена, получает чистый TCP
Неизвестный SNI: перенаправляется на внешний fallback (напр. microsoft.com)
```

**Ключевая деталь:** промежуточный порт `8443` разделяет `proxy_protocol` (для сайтов) и чистый TCP на `1443` (для MTProto). Без этого разделения MTProto ломается.

---

## 📋 Системные требования

| Компонент | Минимум | Рекомендуется |
|---|---|---|
| **ОС** | Ubuntu 20.04 / Debian 11 | Ubuntu 22.04+ |
| **RAM** | 256 MB | 512 MB |
| **CPU** | 1 vCPU | 1+ vCPU |
| **Диск** | 1 GB | 2 GB |
| **Сеть** | Порт 443 (открыт) | — |
| **Docker** | Авто-установка | — |

---

## 🔄 Управление

При повторном запуске скрипт предложит меню:

```
╔══════════════════════════════════════════════════════════════╗
║   Обнаружена существующая установка MTProto-прокси!          ║
╚══════════════════════════════════════════════════════════════╝

  1) Обновить образ       — pull новый образ, контейнер пересоздан
  2) ⚡ Мигрировать на Telemt — переход с MTG v2 на Rust-движок
  3) Переустановить       — с нуля, новый секрет
  4) Удалить всё          — откат nginx из бекапа
  5) Статус               — ссылки + логи
  6) Выход
```

> **Примечание:** Пункт 2 появляется только если текущий движок — MTG v2.

### Ручные команды

```bash
# Статус
docker ps -f name=mtproto-proxy

# Логи (live)
docker logs -f mtproto-proxy

# Перезапуск
docker restart mtproto-proxy

# Обновить образ (Telemt)
docker pull ghcr.io/telemt/telemt:latest && docker rm -f mtproto-proxy && sudo bash deploy_mt.sh
```

---

## 🔍 Что скрипт изменяет на сервере

| Действие | Путь / Область | Откат |
|----------|----------------|-------|
| Установка Docker | `docker.io` (если нет) | `apt remove docker-ce` |
| Запуск контейнера | `mtproto-proxy` | `docker rm -f mtproto-proxy` |
| Конфиг прокси | `/root/.mtproto-proxy.conf` (chmod 600) | `rm -f` |
| Скрипт ротации | `/root/rotate_fallback.sh` | `rm -f` |
| sysctl тюнинг | `/etc/sysctl.d/99-mtproxy-stealth.conf` | `rm -f && sysctl --system` |
| iptables MSS | POSTROUTING + PREROUTING sport/dport 443 | Удаляется опцией «Удалить всё» |
| **SNI-режим:** Nginx stream | `/etc/nginx/stream_mtproxy.conf` | Восстановление из бекапа |
| **SNI-режим:** Патч конфигов | `listen 443` → `listen 127.0.0.1:8443 proxy_protocol` | Бекап в `/etc/nginx_backup_*` |
| **SNI-режим:** Real IP | `/etc/nginx/conf.d/99-mtproto-realip.conf` | `rm -f` |

> Полный откат: запустите `sudo bash deploy_mt.sh` → опция 3 (Удалить всё). Nginx восстановится из таймстемпованного бекапа.

---

## ❓ FAQ

<details>
<summary><b>🔒 Насколько это безопасно?</b></summary>

- Трафик маскируется под легитимный TLS 1.3 запрос (автоматически подбираются трастовые домены с высоким uptime)
- Встроенный TCP-шейпинг (MSS clamping + BBR) эмулирует профиль обычного браузера
- Системы анализа видят стандартный HTTPS-хэндшейк — стоимость детектирования значительно возрастает
- При открытии IP в браузере — пустая страница или ваш сайт
- Секрет хранится в `/root/.mtproto-proxy.conf` (chmod 600)
</details>

<details>
<summary><b>🌐 Будут ли работать мои сайты?</b></summary>

Да. В SNI-режиме скрипт автоматически:
- Детектирует все домены из конфигов Nginx
- Перенаправляет сайты через промежуточный порт
- Сохраняет реальные IP клиентов через `proxy_protocol`
- Создаёт бекап и откатывает при любой ошибке
</details>

<details>
<summary><b>📱 Как подключить на телефоне?</b></summary>

После установки скрипт выдаст готовые ссылки:
- `tg://proxy?server=...` — откроется прямо в Telegram
- `https://t.me/proxy?server=...` — через браузер
- Ручная настройка: Настройки → Данные и память → Прокси
</details>

<details>
<summary><b>⚡ Как обновить / мигрировать на Telemt?</b></summary>

Запустите скрипт повторно. Пункт 1 обновляет текущий движок. Пункт 2 (если стоит MTG v2) мигрирует на Telemt — секрет и ссылки обновятся, нужно будет перенастроить устройства.
</details>

<details>
<summary><b>🗑️ Как полностью удалить?</b></summary>

Запустите скрипт повторно и выберите пункт 3 (Удалить всё). Nginx будет восстановлен из бекапа автоматически.
</details>



---

## 🔧 Технические детали (v0.3)

- **Движок (по умолчанию):** [Telemt](https://github.com/telemt/telemt) — Rust/Tokio, TCP Splicing, Middle-End Pool
- **Движок (legacy):** [mtg v2](https://github.com/9seconds/mtg) — Go, доступен при установке и через миграцию
- **Контейнеризация:** Docker с `restart: unless-stopped`, лимитами памяти (256MB), PIDs (1024)
- **Nginx Stream:** SNI-маршрутизация с `ssl_preread` + `proxy_buffer_size 16k` для фрагментации потока
- **Сетевой стек (Stealth):** `sysctl` тюнинг ядра (FQ, BBR) + `iptables` MSS-clamping 850 байт
- **FakeTLS домен:** Авто-подбор трастовых RF-доменов
- **Конфиг Telemt:** `/root/.telemt/config.toml` (TOML)
- **Конфиг прокси:** `/root/.mtproto-proxy.conf` (chmod 600)

---

## ⚠️ Правовой отказ от ответственности (Disclaimer)

Данный скрипт является инструментом сетевого администрирования с открытым исходным кодом, созданным исключительно для образовательных целей, тестирования сетевой безопасности и защиты приватности в открытых сетях. Автор не несёт ответственности за использование данного программного обеспечения конечными пользователями в целях нарушения местного законодательства их стран. Пожалуйста, соблюдайте законы вашего региона при развёртывании сетевых узлов.

---

## 📄 Лицензия

MIT License. Используйте свободно.

---

<div align="center">

**⭐ Если помогло — поставь звезду!**

*Made with 🛡️ for free internet*

</div>
