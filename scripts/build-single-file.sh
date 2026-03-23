#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# build-single-file.sh — Сборка единого deploy_mt.sh из модулей
# Использование: bash scripts/build-single-file.sh
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

OUT="${ROOT_DIR}/deploy_mt.sh"
TMP="$(mktemp)"

# Порядок модулей — строго фиксированный
MODULES=(
    "lib/common.sh"
    "lib/config.sh"
    "lib/system.sh"
    "lib/docker.sh"
    "lib/network.sh"
    "lib/nginx.sh"
    "lib/actions.sh"
    "lib/output.sh"
    "lib/main.sh"
)

echo "🔧 Building single-file deploy_mt.sh..."
echo ""

# Шапка
cat > "$TMP" <<'HEADER'
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  deploy_mt.sh — MTProto FakeTLS Proxy Deployer (mtg v2)
#  Автоматический деплой MTProto-прокси для Telegram
#  Использование: chmod +x deploy_mt.sh && sudo ./deploy_mt.sh
#
#  ⚠️  GENERATED FILE — DO NOT EDIT DIRECTLY
#  Source of truth: lib/*.sh
#  Rebuild: bash scripts/build-single-file.sh
# ─────────────────────────────────────────────────────────────────
HEADER

# Сборка модулей
for file in "${MODULES[@]}"; do
    filepath="${ROOT_DIR}/${file}"

    if [[ ! -f "$filepath" ]]; then
        echo "❌ Missing: $file" >&2
        rm -f "$TMP"
        exit 1
    fi

    printf '\n\n# >>> BEGIN %s >>>\n' "$file" >> "$TMP"

    # Вырезаем shebang и дублирующий set -euo pipefail из модулей
    sed '/^#!/d; /^set -euo pipefail$/d' "$filepath" >> "$TMP"

    printf '\n# <<< END %s <<<\n' "$file" >> "$TMP"

    echo "  ✅ ${file}"
done

# Финализация
mv "$TMP" "$OUT"
chmod +x "$OUT"

echo ""
echo "✅ Built: ${OUT}"
echo "   Size: $(wc -c < "$OUT") bytes, $(wc -l < "$OUT") lines"

# Проверка синтаксиса
echo ""
echo "🔍 Checking syntax..."
if bash -n "$OUT"; then
    echo "✅ Syntax OK"
else
    echo "❌ Syntax check FAILED!" >&2
    exit 1
fi
