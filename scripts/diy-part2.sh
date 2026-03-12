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

echo ">>> CB-Shield-Q30 DIY Part 2 执行完毕"
