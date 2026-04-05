# ══════════════════════════════════════════════════════════════════
# lib/common.sh — Общий фундамент: strict mode, цвета, иконки, логгеры, константы
# ══════════════════════════════════════════════════════════════════

# ── Strict Mode ──
set -euo pipefail

# ── Цвета ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Иконки (UTF-8) ──
ICON_OK="✅"
ICON_ERR="❌"
ICON_WARN="⚠️ "
ICON_INFO="ℹ️ "
ICON_ROCKET="🚀"
ICON_GEAR="⚙️ "
ICON_KEY="🔑"
ICON_LINK="🔗"
ICON_CHECK="✔"
ICON_DOCKER="🐳"
ICON_SHIELD="🛡️ "
ICON_CLOCK="⏱️ "

# ── Логгеры ──
log_info()    { echo -e "${BLUE}${ICON_INFO}  [INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}${ICON_OK} [  OK ]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}${ICON_WARN} [WARN]${RESET}  $*"; }
log_err()     { echo -e "${RED}${ICON_ERR} [ ERR]${RESET}  $*"; }
log_step()    { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${RESET}"; }
log_sub()     { echo -e "    ${CYAN}▸${RESET} $*"; }
log_dim()     { echo -e "    ${WHITE}$*${RESET}"; }
separator()   { echo -e "${GRAY}$(printf '─%.0s' {1..60})${RESET}"; }

# ── Readonly-константы ──
readonly CONFIG_FILE="/root/.mtproto-proxy.conf"
readonly CONTAINER_NAME="mtproto-proxy"
readonly MTG_IMAGE="nineseconds/mtg:2"
readonly DNS_RESOLVER="1.1.1.1"
readonly ULIMIT_NOFILE=51200
readonly EXTERNAL_FALLBACK="www.microsoft.com:443"
readonly STREAM_CONF="/etc/nginx/stream_mtproxy.conf"
readonly NGINX_SITE_PORT=8443
readonly MTG_INTERNAL_PORT=1443
readonly FALLBACK_PORT=8443
readonly SYSCTL_CONF="/etc/sysctl.d/99-mtproxy-stealth.conf"
readonly REALIP_CONF="/etc/nginx/conf.d/99-mtproto-realip.conf"
readonly ROTATE_SCRIPT="/root/rotate_fallback.sh"

# Telemt (Rust) — новый движок
readonly TELEMT_IMAGE="ghcr.io/telemt/telemt:latest"
readonly TELEMT_CONFIG_DIR="/root/.telemt"
readonly TELEMT_CONFIG_FILE="/root/.telemt/config.toml"

# РФ-дружественные домены (РКН не блочит, ASN безопасен)
readonly RF_DOMAINS=("yandex.ru" "mail.ru" "ok.ru" "sberbank.ru" "beeline.ru" "rambler.ru" "rutube.ru")

# ── Mutable runtime state ──
PROXY_PORT="${PROXY_PORT:-443}"
FAKETLS_DOMAIN=""
SNI_MODE=false
SERVER_IP="${SERVER_IP:-}"
SECRET=""
PROXY_ENGINE="${PROXY_ENGINE:-telemt}"  # "telemt" (Rust, рекомендуется) или "mtg" (Go, legacy)
