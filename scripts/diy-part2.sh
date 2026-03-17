#!/bin/bash
set -e

echo ">>> CB-Shield-Q30 DIY Part 2 start"

# Copy custom packages
if [ -d "$GITHUB_WORKSPACE/luci-theme-cbshield" ]; then
    cp -r "$GITHUB_WORKSPACE/luci-theme-cbshield" package/luci-theme-cbshield
fi

if [ -d "$GITHUB_WORKSPACE/packages/cb-riskcontrol" ]; then
    cp -r "$GITHUB_WORKSPACE/packages/cb-riskcontrol" package/cb-riskcontrol
fi

if [ -d "$GITHUB_WORKSPACE/files" ]; then
    mkdir -p files
    cp -a "$GITHUB_WORKSPACE/files/." files/
fi

# Keep custom packages under package/custom
mkdir -p package/custom
mv package/cb-riskcontrol package/custom/ 2>/dev/null || true
mv package/luci-theme-cbshield package/custom/ 2>/dev/null || true

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

# Keep compatibility patch minimal
find ./feeds/kwrt -name "Makefile" -exec sed -i 's/PKG_BUILD_DEPENDS:=.*mbedtls/PKG_BUILD_DEPENDS:=mbedtls/g' {} + 2>/dev/null || true

echo ">>> CB-Shield-Q30 DIY Part 2 done"
