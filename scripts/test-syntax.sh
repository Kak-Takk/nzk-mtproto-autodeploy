#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# test-syntax.sh — Статическая проверка синтаксиса всех .sh файлов
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔍 Syntax check for all .sh files..."
echo ""

FAIL=0

# Проверяем модули
for file in "${ROOT_DIR}"/lib/*.sh; do
    if bash -n "$file" 2>/dev/null; then
        echo "  ✅ $(basename "$file")"
    else
        echo "  ❌ $(basename "$file")"
        ((FAIL++))
    fi
done

# Проверяем root-level скрипты
for file in deploy_mt.sh smoke-mtproto.sh rotate_fallback.sh; do
    filepath="${ROOT_DIR}/${file}"
    if [[ -f "$filepath" ]]; then
        if bash -n "$filepath" 2>/dev/null; then
            echo "  ✅ ${file}"
        else
            echo "  ❌ ${file}"
            ((FAIL++))
        fi
    fi
done

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "✅ All syntax checks passed!"
else
    echo "❌ ${FAIL} file(s) failed syntax check!" >&2
    exit 1
fi

# ShellCheck (если установлен)
if command -v shellcheck &>/dev/null; then
    echo ""
    echo "🔍 Running ShellCheck..."
    shellcheck -x "${ROOT_DIR}"/lib/*.sh "${ROOT_DIR}"/rotate_fallback.sh "${ROOT_DIR}"/scripts/*.sh 2>&1 || true
else
    echo ""
    echo "ℹ️  ShellCheck not installed — skipping (apt install shellcheck)"
fi
