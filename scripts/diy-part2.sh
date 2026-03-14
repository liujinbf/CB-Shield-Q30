#!/bin/bash
# ============================================================
# CB-Shield-Q30 自定义脚本 Part 2
# 在 feeds 安装后、编译前执行
# 用途：复制自定义包、修改默认配置、设置主题
# ============================================================

echo ">>> CB-Shield-Q30 DIY Part 2 开始执行..."

# 复制自定义 LuCI 主题到 feeds 目录
if [ -d "$GITHUB_WORKSPACE/luci-theme-cbshield" ]; then
    cp -r "$GITHUB_WORKSPACE/luci-theme-cbshield" package/luci-theme-cbshield
    echo "  已复制 luci-theme-cbshield 到 package/"
fi

# 复制风控包到 package 目录
if [ -d "$GITHUB_WORKSPACE/packages/cb-riskcontrol" ]; then
    cp -r "$GITHUB_WORKSPACE/packages/cb-riskcontrol" package/cb-riskcontrol
    echo "  已复制 cb-riskcontrol 到 package/"
fi

# 复制自定义文件系统覆盖
if [ -d "$GITHUB_WORKSPACE/files" ]; then
    cp -r "$GITHUB_WORKSPACE/files" files
    echo "  已复制 files/ 文件系统覆盖"
fi

# 修改默认 IP（可选，根据需要调整）
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# 修改主机名
sed -i "s/hostname='OpenWrt'/hostname='CB-Shield-Q30'/g" package/base-files/files/bin/config_generate

# 修改默认时区为中国
sed -i "s/timezone='UTC'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
sed -i "s/zonename='UTC'/zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

# 修改 banner
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

# 1. 修正 JCG Q30 Pro 的 DTS 引导参数 (关键：移除 root=/dev/fit0 以适配第三方 U-Boot)
DTS_FILE="target/linux/mediatek/dts/mt7981-jcg-q30-pro.dts"
if [ -f "$DTS_FILE" ]; then
    sed -i 's/root=\/dev\/fit0 rootwait//g' "$DTS_FILE"
    echo "  已修正 DTS 引导参数: $DTS_FILE"
fi

# 2. 适配 Kwrt 风格的镜像生成格式 (filogic.mk)
cat << 'EOF' > patch_q30_format.sh
#!/bin/bash
MK_FILE="target/linux/mediatek/image/filogic.mk"
if [ -f "$MK_FILE" ]; then
    # 定位 Device/jcg_q30-pro 定义块并进行替换为 Kwrt 风格
    sed -i '/define Device\/jcg_q30-pro/,/endef/c\
define Device/jcg_q30-pro\
  DEVICE_VENDOR := JCG\
  DEVICE_MODEL := Q30 PRO (Kwrt Style)\
  DEVICE_DTS := mt7981b-jcg-q30-pro\
  DEVICE_DTS_DIR := ../dts\
  DEVICE_DTC_FLAGS := --pad 4096\
  UBINIZE_OPTS := -E 5\
  BLOCKSIZE := 128k\
  PAGESIZE := 2048\
  IMAGE_SIZE := 114816k\
  KERNEL_IN_UBI := 1\
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware\
  IMAGES += factory.bin\
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)\
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata\
endef\
' "$MK_FILE"
    echo "  已成功注入 Kwrt 格式打包补丁: $MK_FILE"
fi
EOF
chmod +x patch_q30_format.sh
./patch_q30_format.sh
rm patch_q30_format.sh

# === 固件极致瘦身与安全加固 (由 Antigravity 注入) ===

# 1. 彻底禁用全局 IPv6 (针对 config_generate)
sed -i 's/.*ip6assign.*/\t\tset network.lan.ip6assign=0/g' package/base-files/files/bin/config_generate
sed -i 's/.*ip6gw.*/\t\tset network.wan.ip6gw=0/g' package/base-files/files/bin/config_generate

# 2. 移除 uhttpd 服务器特征响应头 (隐私增强)
# 修改 uhttpd 的默认配置生成，禁用版本显示和干扰探测
if [ -f "package/network/services/uhttpd/files/uhttpd.config" ]; then
    sed -i '/config uhttpd main/a \	option banner 0' package/network/services/uhttpd/files/uhttpd.config
fi

# 3. 禁用一些消耗资源的 mDNS 组播服务守护 (防局域网探测)
# 针对 avahi, mdns 等服务 (如果存在)
sed -i 's/enabled=1/enabled=0/g' package/feeds/packages/avahi/files/avahi-daemon.init 2>/dev/null

# 3. 修正 CMake 版本要求 (解决 rpcd-mod-luci 要求的 3.31 与环境 3.26 的冲突)
# 遍历 feeds 目录，将所有 CMakeLists.txt 中的 3.31 要求降低到 3.26
find ./feeds -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.26)/g' {} +

echo "  已完成固件精简、IPv6 封杀以及 CMake 版本补丁注入。"

echo ">>> CB-Shield-Q30 DIY Part 2 执行完毕"
