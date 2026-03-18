#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-prepare}"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[env] missing command: $cmd" >&2
        return 1
    fi
}

UNAME_S="$(uname -s 2>/dev/null || echo unknown)"

case "$UNAME_S" in
    Linux) ;;
    *)
        cat >&2 <<EOF
[env] unsupported host for OpenWrt native build: $UNAME_S
[env] please use one of these environments:
  1. Ubuntu / Debian
  2. WSL2 Ubuntu
  3. GitHub Actions workflow
EOF
        exit 1
        ;;
esac

missing=0
for cmd in bash git make perl python3; do
    if ! require_cmd "$cmd"; then
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    cat >&2 <<'EOF'
[env] OpenWrt build prerequisites are incomplete.
[env] install the standard OpenWrt build dependencies first, then retry.
EOF
    exit 1
fi

if [ "$MODE" = "build" ]; then
    for cmd in gcc g++ tar gzip; do
        if ! require_cmd "$cmd"; then
            missing=1
        fi
    done
fi

if [ "$missing" -ne 0 ]; then
    exit 1
fi

echo "[env] build environment looks usable"
