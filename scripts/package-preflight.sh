#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <openwrt_dir>"
  exit 1
fi

OPENWRT_DIR="$(cd "$1" && pwd)"
cd "$OPENWRT_DIR"

targets=(
  "package/custom/cb-riskcontrol/compile"
  "package/custom/luci-theme-cbshield/compile"
)

for target in "${targets[@]}"; do
  echo "[preflight] $target"
  make "$target" -j"$(nproc)" V=s
done
