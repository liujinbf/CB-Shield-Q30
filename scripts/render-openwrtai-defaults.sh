#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$REPO_ROOT/.work"
OUTPUT_PATH="$WORK_DIR/cbshield-openwrtai-defaults.sh"
MODE="file"

usage() {
    cat <<'EOF'
用法:
  bash scripts/render-openwrtai-defaults.sh
  bash scripts/render-openwrtai-defaults.sh --stdout
  bash scripts/render-openwrtai-defaults.sh --output /path/to/file
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --stdout)
            MODE="stdout"
            shift
            ;;
        --output)
            OUTPUT_PATH="$2"
            MODE="file"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

DEFAULTS_CONTENT=$(cat <<'EOF'
#!/bin/sh
# CB-Shield openwrt.ai defaults

uci -q batch <<'UCI_EOF'
set luci.main.lang='zh_cn'
set luci.main.mediaurlbase='/luci-static/argon'
set luci.main.homepage='admin/cbshield/dashboard'
set luci.themes.Argon='/luci-static/argon'
commit luci
UCI_EOF

for svc in cb-riskcontrol cb-portal cb-healthcheck cb-ha-monitor cb-dns-guard; do
    [ -x "/etc/init.d/$svc" ] && /etc/init.d/$svc enable 2>/dev/null
done
EOF
)

if [ "$MODE" = "stdout" ]; then
    printf '%s\n' "$DEFAULTS_CONTENT"
    exit 0
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
printf '%s\n' "$DEFAULTS_CONTENT" > "$OUTPUT_PATH"
chmod +x "$OUTPUT_PATH"
echo "defaults_path=$OUTPUT_PATH"
