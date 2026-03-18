#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SMOKE=1

usage() {
    cat <<'EOF'
用法:
  bash scripts/prepare-openwrtai-upload.sh
  bash scripts/prepare-openwrtai-upload.sh --skip-smoke
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-smoke)
            RUN_SMOKE=0
            shift
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

if [ "$RUN_SMOKE" -eq 1 ]; then
    bash "$SCRIPT_DIR/ci-smoke.sh" "$REPO_ROOT"
fi

bash "$SCRIPT_DIR/build-openwrtai-overlay.sh"
bash "$SCRIPT_DIR/render-openwrtai-defaults.sh"

cat <<EOF
准备完成:
  覆盖包: $REPO_ROOT/.work/cbshield-openwrtai-overlay.tgz
  defaults: $REPO_ROOT/.work/cbshield-openwrtai-defaults.sh
  清单: $REPO_ROOT/.work/openwrtai-overlay.manifest
EOF
