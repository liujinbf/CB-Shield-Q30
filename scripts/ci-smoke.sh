#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

echo "[smoke] check required package files"
required_files=(
  "packages/cb-riskcontrol/files/cb-healthcheck.sh"
  "packages/cb-riskcontrol/files/cb-ha-monitor.sh"
  "packages/cb-riskcontrol/files/cb-dns-guard.sh"
  "packages/cb-riskcontrol/files/cb-policy-engine.sh"
  "packages/cb-riskcontrol/files/cb-safe-upgrade.sh"
  "packages/cb-riskcontrol/files/cb-wizard.sh"
  "luci-theme-cbshield/luasrc/controller/cbshield/api.lua"
  "luci-theme-cbshield/luasrc/controller/cbshield/index.lua"
)
for f in "${required_files[@]}"; do
  test -f "$f"
done

echo "[smoke] check shell syntax"
while IFS= read -r f; do
  sh -n "$f"
done < <(find packages/cb-riskcontrol/files -maxdepth 1 -type f -name "*.sh" | sort)
sh -n scripts/diy-part1.sh
sh -n scripts/diy-part2.sh
sh -n files/etc/uci-defaults/90_v3_optimizations

echo "[smoke] check lua syntax"
if command -v luac >/dev/null 2>&1; then
  luac -p luci-theme-cbshield/luasrc/controller/cbshield/index.lua
  luac -p luci-theme-cbshield/luasrc/controller/cbshield/api.lua
fi

echo "[smoke] check required API routes"
api_file="luci-theme-cbshield/luasrc/controller/cbshield/api.lua"
grep -q '"api", "health"' "$api_file"
grep -q '"api", "ha_status"' "$api_file"
grep -q '"api", "dns_status"' "$api_file"
grep -q '"api", "events"' "$api_file"
grep -q '"api", "wizard_apply"' "$api_file"
grep -q '"api", "apply_template"' "$api_file"
grep -q '"api", "upgrade_check"' "$api_file"

echo "[smoke] check defaults and first-boot wizard"
grep -q "wizard_required" files/etc/uci-defaults/90_v3_optimizations
grep -q "CB-Shield-Office" files/etc/uci-defaults/90_v3_optimizations
grep -q "cb-healthcheck" files/etc/uci-defaults/90_v3_optimizations
grep -q "cb-ha-monitor" files/etc/uci-defaults/90_v3_optimizations
grep -q "cb-dns-guard" files/etc/uci-defaults/90_v3_optimizations
grep -q "cb-policy-engine" files/etc/uci-defaults/90_v3_optimizations

echo "[smoke] done"
