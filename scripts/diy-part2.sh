#!/bin/bash
set -e

echo ">>> CB-Shield-Q30 DIY Part 2 start"

SAFE_BASELINE="${CB_SAFE_BASELINE:-0}"

sync_dir() {
    local src="$1"
    local dst="$2"

    [ -d "$src" ] || return 0
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
}

# Copy custom packages
sync_dir "$GITHUB_WORKSPACE/luci-theme-cbshield" package/custom/luci-theme-cbshield
sync_dir "$GITHUB_WORKSPACE/packages/cb-riskcontrol" package/custom/cb-riskcontrol

mkdir -p package/custom

if [ "$SAFE_BASELINE" = "1" ]; then
    echo ">>> Safe baseline enabled: skip repo files overlay and device-level board patches"
else
    if [ -d "$GITHUB_WORKSPACE/files" ]; then
        mkdir -p files
        cp -a "$GITHUB_WORKSPACE/files/." files/
    fi

    # Base defaults
    sed -i "s/hostname='OpenWrt'/hostname='CB-Shield-Q30'/g" package/base-files/files/bin/config_generate
    sed -i "s/timezone='UTC'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
    sed -i "s/zonename='UTC'/zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

    cat > package/base-files/files/etc/banner << 'EOF'
  ____  ____        ____  _     _      _     _
 / ___|| __ )      / ___|| |__ (_) ___| | __| |
| |    |  _ \ _____\___ \| '_ \| |/ _ \ |/ _` |
| |___ | |_) |_____|___) | | | | |  __/ | (_| |
 \____||____/      |____/|_| |_|_|\___|_|\__,_|

  Q30 Router | KJWS Network Security
  Build: $(date +%Y%m%d)
 -----------------------------------------------------
EOF

    # Remove fit0 bootarg for third-party U-Boot
    find target/linux/mediatek/dts -name "*jcg*q30*.dts" -exec sed -i 's/root=\/dev\/fit0 rootwait//g' {} +

    # Replace full jcg_q30-pro block to stable BIN output format
    MK_FILE="target/linux/mediatek/image/filogic.mk"
    if [ -f "$MK_FILE" ]; then
        sed -i '/define Device\/jcg_q30-pro/,/endef/c\
define Device/jcg_q30-pro\
  DEVICE_VENDOR := JCG\
  DEVICE_MODEL := Q30 PRO\
  DEVICE_DTS := mt7981b-jcg-q30-pro\
  DEVICE_DTS_DIR := ../dts\
  UBINIZE_OPTS := -E 5\
  BLOCKSIZE := 128k\
  PAGESIZE := 2048\
  IMAGE_SIZE := 114816k\
  KERNEL_IN_UBI := 1\
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware\
  IMAGES += factory.bin\
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)\
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata\
endef' "$MK_FILE"
    fi

    # Keep Wi-Fi enabled by default
    sed -i 's/set ${s}.disabled=1/set ${s}.disabled=0/g' package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc || true
fi

# Keep compatibility patch minimal
find ./feeds/kwrt -name "Makefile" -exec sed -i 's/PKG_BUILD_DEPENDS:=.*mbedtls/PKG_BUILD_DEPENDS:=mbedtls/g' {} + 2>/dev/null || true

echo ">>> CB-Shield-Q30 DIY Part 2 done"
