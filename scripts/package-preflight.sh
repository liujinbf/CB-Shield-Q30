#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <openwrt_dir>"
  exit 1
fi

OPENWRT_DIR="$(cd "$1" && pwd)"
cd "$OPENWRT_DIR"

required_files=(
  "package/custom/cb-riskcontrol/Makefile"
  "package/custom/luci-theme-cbshield/Makefile"
)

for file in "${required_files[@]}"; do
  echo "[preflight] check $file"
  test -f "$file"
done

echo "[preflight] validate package names"
grep -q "Package/cb-riskcontrol" package/custom/cb-riskcontrol/Makefile
grep -q "LUCI_TITLE:=CB-Shield" package/custom/luci-theme-cbshield/Makefile

echo "[preflight] custom package sources ready"
