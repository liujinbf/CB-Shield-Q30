#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

echo "[smoke] check required package files"
required_files=(
  "packages/cb-riskcontrol/files/cb-healthcheck.sh"
  "packages/cb-riskcontrol/files/cb-ha-monitor.sh"
  "packages/cb-riskcontrol/files/cb-dns-guard.sh"
  "packages/cb-riskcontrol/files/cb-safe-upgrade.sh"
  "packages/cb-riskcontrol/files/cb-wizard.sh"
  "packages/cb-riskcontrol/files/cb-openclash-setup.sh"
  "luci-theme-cbshield/luasrc/controller/cbshield/api.lua"
  "luci-theme-cbshield/luasrc/controller/cbshield/index.lua"
  "luci-theme-cbshield/luasrc/view/cbshield/dashboard.htm"
  "luci-theme-cbshield/luasrc/view/cbshield/network_status.htm"
  "luci-theme-cbshield/root/etc/uci-defaults/80_cbshield-theme"
  "files/www/cb-portal/portal_config.json"
  "scripts/cbshield-kwrt-install.sh"
  "scripts/build-kwrt-runtime-bundle.sh"
)
for f in "${required_files[@]}"; do
  test -f "$f"
done
test ! -e "portal_config.json"
test ! -e "files/etc/config/cb-riskcontrol"

echo "[smoke] check shell syntax"
while IFS= read -r f; do
  bash -n "$f"
done < <(find packages/cb-riskcontrol/files -maxdepth 1 -type f -name "*.sh" | sort)
bash -n scripts/diy-part1.sh
bash -n scripts/diy-part2.sh
bash -n scripts/build-openwrtai-overlay.sh
bash -n scripts/build-kwrt-runtime-bundle.sh
sh -n scripts/cbshield-kwrt-install.sh
sh -n files/etc/uci-defaults/90_v3_optimizations
sh -n luci-theme-cbshield/root/etc/uci-defaults/80_cbshield-theme

echo "[smoke] check lua syntax"
if command -v luac >/dev/null 2>&1; then
  luac -p luci-theme-cbshield/luasrc/controller/cbshield/index.lua
  luac -p luci-theme-cbshield/luasrc/controller/cbshield/api.lua
fi

echo "[smoke] check javascript syntax"
if command -v node >/dev/null 2>&1; then
  node --check luci-theme-cbshield/htdocs/luci-static/cbshield/js/dashboard.js
  node -e 'const fs=require("fs"); const s=fs.readFileSync(process.argv[1], "utf8"); const m=s.match(/<script>([\s\S]*)<\/script>/); if (!m) process.exit(1); new Function(m[1]);' \
    luci-theme-cbshield/luasrc/view/cbshield/wizard.htm
fi

echo "[smoke] check portal config json"
if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool files/www/cb-portal/portal_config.json >/dev/null
elif command -v node >/dev/null 2>&1; then
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
    files/www/cb-portal/portal_config.json
else
  echo "[smoke] missing python3 or node for json validation"
  exit 1
fi

echo "[smoke] check required API routes"
api_file="luci-theme-cbshield/luasrc/controller/cbshield/api.lua"
grep -q '"api", "sysinfo"' "$api_file"
grep -q '"api", "riskstatus"' "$api_file"
grep -q '"api", "runcheck"' "$api_file"
grep -q '"api", "network"' "$api_file"
grep -q '"api", "health"' "$api_file"
grep -q '"api", "ha_status"' "$api_file"
grep -q '"api", "dns_status"' "$api_file"
grep -q '"api", "events"' "$api_file"
grep -q '"api", "wizard_apply"' "$api_file"
grep -q '"api", "upgrade_check"' "$api_file"

echo "[smoke] check defaults and first-boot wizard"
grep -q "wizard_required" files/etc/uci-defaults/90_v3_optimizations
grep -q "CB-Shield-Office" files/etc/uci-defaults/90_v3_optimizations
grep -q "THEME_PATH='/luci-static/argon'" files/etc/uci-defaults/90_v3_optimizations
grep -q "office_24g" files/etc/uci-defaults/90_v3_optimizations
grep -q "office_5g" files/etc/uci-defaults/90_v3_optimizations
grep -q "cb-healthcheck" files/etc/uci-defaults/90_v3_optimizations
grep -q "cb-ha-monitor" files/etc/uci-defaults/90_v3_optimizations
grep -q "cb-dns-guard" files/etc/uci-defaults/90_v3_optimizations
if grep -q "cb-policy-engine" files/etc/uci-defaults/90_v3_optimizations; then
  echo "[smoke] unexpected cb-policy-engine reference"
  exit 1
fi
if grep -R -n "enforce_shop_dns_hijack" packages/cb-riskcontrol files luci-theme-cbshield >/dev/null 2>&1; then
  echo "[smoke] unexpected shop dns hijack reference"
  exit 1
fi

echo "[smoke] check config naming"
grep -q "check_proxy" packages/cb-riskcontrol/files/cb-health.conf
grep -q "check_proxy" packages/cb-riskcontrol/files/cb-healthcheck.sh
grep -q "luci-static/bootstrap" luci-theme-cbshield/root/etc/uci-defaults/80_cbshield-theme
grep -q "cbshield-kwrt-runtime.tgz" scripts/cbshield-kwrt-install.sh

echo "[smoke] check kwrt passwall profile is rust-free"
grep -q "^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client is not set$" profiles/stable.config
grep -q "^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS is not set$" profiles/stable.config
grep -q "^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_tuic_client is not set$" profiles/stable.config
grep -q "rm -rf feeds/kiddin9/webd feeds/kiddin9/luci-app-webd" scripts/build-kwrt-passwall-in-docker.sh

echo "[smoke] done"
