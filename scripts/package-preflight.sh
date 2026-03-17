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
  # 干净树上并行预编译自定义包会打乱 OpenWrt 的依赖构建顺序。
  # 这里改为串行执行，优先保证首次构建稳定。
  make "$target" -j1 V=s
done
