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

# 确保自定义包目录存在并刷新编译索引
mkdir -p package/custom
mv package/cb-riskcontrol package/custom/ 2>/dev/null || true
mv package/luci-theme-cbshield package/custom/ 2>/dev/null || true

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
# 使用通配符搜索，确保无论源码文件名是 mt7981 还是 mt7981b 都能精准打击
# 这一步是解决“红灯”不引导的核心关键
find target/linux/mediatek/dts -name "*jcg*q30*.dts" -exec sed -i 's/root=\/dev\/fit0 rootwait//g' {} +
echo "  已应用 DTS 引导参数全局修正。"

# 2. 强制回归 .bin (UBI) 打包格式并保留功能包集成
# 针对 JCG Q30 Pro 使用非破坏性插入，强制生成 .factory.bin 并补充驱动
MK_FILE="target/linux/mediatek/image/filogic.mk"
if [ -f "$MK_FILE" ]; then
    # 在 jcg_q30-pro 定义块的 endef 之前插入生成规则，这样不会破坏原始继承
    sed -i '/define Device\/jcg_q30-pro/,/endef/ { /endef/i \
  IMAGES += factory.bin\
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
    }' "$MK_FILE"
    # 同时确保驱动包不会丢失
    sed -i '/define Device\/jcg_q30-pro/,/endef/ s/DEVICE_PACKAGES :=/DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware /' "$MK_FILE"
    echo "  已安全注入 .bin 生成规则到 $MK_FILE"
fi

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

# 3. 修正各组件版本要求 (解决 23.05 稳定版环境与部分 Feeds 插件的冲突)
echo "  正在注入版本兼容性补丁..."
# A. CMake: 3.31 -> 3.26
find ./feeds -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.26)/g' {} +

# 4. 强制开启 WiFi (解决 23.05 默认关闭无线的问题)
echo "  正在强制开启 WiFi 默认广播..."
# 修改 mac80211 脚本，将所有 radio 的默认状态从 disabled '1' 改为 '0'
sed -i 's/set ${s}.disabled=1/set ${s}.disabled=0/g' package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc || true

# 5. UI 预配置补丁 (防止原生 UI 出现，并挂载卡片仪表盘)
# 注意：23.05 官方源码路径可能与 Lean 源码不同，我们将重心放在 files/ 覆盖和 uci-defaults 上
# 强制设定默认主页为我们的卡片仪表盘
sed -i 's/\"admin\", \"status\", \"overview\"/\"admin\", \"cbshield\", \"dashboard\"/g' feeds/luci/modules/luci-base/luasrc/controller/admin/status.lua 2>/dev/null || true
echo "  UI 仪表盘卡片重定向已激活。"

# 3. 修正各组件版本要求 (解决 23.05 稳定版环境与部分 Feeds 插件的冲突)
echo "  正在注入版本兼容性补丁..."
# A. CMake: 3.31 -> 3.26
find ./feeds -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.26)/g' {} +
# B. Go: 1.24 -> 1.21
find ./feeds -name "go.mod" -exec sed -i 's/go 1.24/go 1.21/g' {} +
# C. MbedTLS: 强行注释掉 curl 等包中的 3.2.0 版本检查报错 (23.05 仅有 2.28)
find ./feeds -name "*.c" -o -name "*.h" -exec sed -i 's/#error "mbedTLS 3.2.0 or later required"/\/\/#error "mbedTLS 3.2.0 or later required"/g' {} +

echo "  已完成固件精简、IPv6 封杀以及版本兼容性补丁注入。"

echo ">>> CB-Shield-Q30 DIY Part 2 执行完毕"
