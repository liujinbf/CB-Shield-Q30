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

apply_repo_patch() {
    local patch_file="$1"

    [ -f "$patch_file" ] || {
        echo ">>> Missing patch: $patch_file"
        exit 1
    }

    if patch -p1 -N --dry-run < "$patch_file" >/dev/null 2>&1; then
        echo ">>> Applying patch $(basename "$patch_file")"
        patch -p1 -N < "$patch_file"
        return 0
    fi

    if patch -p1 -R --dry-run < "$patch_file" >/dev/null 2>&1; then
        echo ">>> Patch already applied: $(basename "$patch_file")"
        return 0
    fi

    echo ">>> Patch cannot be applied cleanly: $patch_file"
    exit 1
}

rewrite_q30_image_recipe() {
    python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("target/linux/mediatek/image/filogic.mk")
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r"define Device/jcg_q30-pro\n.*?^endef\nTARGET_DEVICES \+= jcg_q30-pro\n",
    re.S | re.M,
)
replacement = """define Device/jcg_q30-pro
  DEVICE_VENDOR := JCG
  DEVICE_MODEL := Q30 PRO
  DEVICE_DTS := mt7981b-jcg-q30-pro
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114816k
  KERNEL_IN_UBI := 1
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += jcg_q30-pro
"""
updated, count = pattern.subn(replacement, text, count=1)
if count != 1:
    sys.exit(">>> Unable to rewrite jcg_q30-pro image recipe")
path.write_text(updated, encoding="utf-8")
PY
}

apply_kwrt_q30_boot_compat() {
    find target/linux/mediatek/dts -name "*jcg*q30*.dts" -exec \
        sed -i -E \
            -e 's/ ?root=\/dev\/fit0 rootwait//' \
            -e '/rootdisk =/d' \
            -e '/bootargs.* = ""/d' {} +
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

    # Match the working Kwrt Q30 boot chain for third-party recovery U-Boot.
    apply_kwrt_q30_boot_compat

    # Apply Q30 board patch and rewrite the image recipe in-place to avoid patch context drift.
    apply_repo_patch "$GITHUB_WORKSPACE/patches/mediatek/09-jcg-q30-pro-dts.patch"
    rewrite_q30_image_recipe

    # Keep Wi-Fi enabled by default
    sed -i 's/set ${s}.disabled=1/set ${s}.disabled=0/g' package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc || true
fi

# Validate the final Q30 device definition before defconfig runs.
grep -A12 '^define Device/jcg_q30-pro' target/linux/mediatek/image/filogic.mk | grep -q 'DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware'
grep -A12 '^define Device/jcg_q30-pro' target/linux/mediatek/image/filogic.mk | grep -q 'IMAGE/factory.bin := append-ubi'
grep -q 'mediatek,mtd-eeprom = <&factory 0x0>;' target/linux/mediatek/dts/mt7981b-jcg-q30-pro.dts
grep -q 'compatible = "linux,ubi";' target/linux/mediatek/dts/mt7981b-jcg-q30-pro.dts
grep -q 'volname = "fit";' target/linux/mediatek/dts/mt7981b-jcg-q30-pro.dts
grep -q 'compatible = "fixed-layout";' target/linux/mediatek/dts/mt7981b-jcg-q30-pro.dts
grep -q 'mediatek,nmbm;' target/linux/mediatek/dts/mt7981b-jcg-q30-pro.dts
! grep -q 'root=\/dev\/fit0 rootwait' target/linux/mediatek/dts/mt7981b-jcg-q30-pro.dts
! grep -q 'rootdisk = <&ubi_rootdisk>;' target/linux/mediatek/dts/mt7981b-jcg-q30-pro.dts
grep -A12 'jcg,q30-pro' target/linux/mediatek/filogic/base-files/etc/board.d/02_network | grep -q 'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan'
grep -A8 'jcg,q30-pro' target/linux/mediatek/filogic/base-files/etc/hotplug.d/ieee80211/11_fix_wifi_mac | grep -q 'get_mac_label'

# Keep compatibility patch minimal
find ./feeds/kwrt -name "Makefile" -exec sed -i 's/PKG_BUILD_DEPENDS:=.*mbedtls/PKG_BUILD_DEPENDS:=mbedtls/g' {} + 2>/dev/null || true

echo ">>> CB-Shield-Q30 DIY Part 2 done"
