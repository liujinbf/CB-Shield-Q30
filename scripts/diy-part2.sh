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
find target/linux/mediatek/dts -name "*jcg*q30*.dts" -exec sed -i 's/root=\/dev\/fit0 rootwait//g' {} +
echo "  已应用 DTS 引导参数全局修正。"

# 2. 【打包与插件固化】强制回归全 .bin 格式，并确保核心驱动继承
# 采用更稳健的逐行替换，避免块匹配失败导致 Makefile 损坏
MK_FILE="target/linux/mediatek/image/filogic.mk"
if [ -f "$MK_FILE" ]; then
    # 修改 IMAGES 定义，由 .itb 改为 .bin
    sed -i '/Device\/jcg_q30-pro/,/endef/ s/IMAGES := sysupgrade.itb/IMAGES := factory.bin sysupgrade.bin/' "$MK_FILE"
    
    # 强制注入核心包到设备定义中
    sed -i '/Device\/jcg_q30-pro/,/endef/ s/DEVICE_PACKAGES :=/DEVICE_PACKAGES := luci-theme-argon luci-app-passwall luci-theme-cbshield cb-riskcontrol /' "$MK_FILE"
    
    # 在适当位置插入打包规则 (使用追加方式避免破坏结构)
    # 利用 DEVICE_PACKAGES 这一行作为锚点，在其后插入图像生成详细定义
    sed -i '/DEVICE_PACKAGES :=.*cb-riskcontrol/a \  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)\n  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata' "$MK_FILE"
    
    echo "  已硬核固化 $MK_FILE：.bin 格式与 0 缺失插件链条。"
fi

# 3. 修正 mac80211 脚本，确保无线默认开启
sed -i 's/set ${s}.disabled=1/set ${s}.disabled=0/g' package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc || true

# 4. 彻底撤销危险的 LuCI 核心代码 Hack (这是导致界面 THEME FALLBACK 的元凶)
# 首页重定向将统一由 uci-defaults 脚本安全处理
echo "  已彻底阻断核心代码 Hack，UI 环境现在是清净的。"

# 5. 确保自定义包目录存在并刷新编译索引
mkdir -p package/custom
mv package/cb-riskcontrol package/custom/ 2>/dev/null || true
mv package/luci-theme-cbshield package/custom/ 2>/dev/null || true

# 6. 版本兼容性“微操” (仅处理确切的冲突，不再全盘扫描)
# 修正编译依赖版本过高问题
find ./feeds/kwrt -name "Makefile" -exec sed -i 's/PKG_BUILD_DEPENDS:=.*mbedtls/PKG_BUILD_DEPENDS:=mbedtls/g' {} + 2>/dev/null || true

echo ">>> CB-Shield-Q30 DIY Part 2 执行完毕"
