#!/bin/bash
# ============================================================
# CB-Shield-Q30 自定义脚本 Part 1
# 在 feeds 更新后、安装前执行
# 用途：添加自定义 feeds 源、修改 feed 配置
# ============================================================

echo ">>> CB-Shield-Q30 DIY Part 1 开始执行..."

# 1. 准备自定义 Feeds 存储目录 (避开系统 feeds 文件夹)
mkdir -p custom_feeds
echo "  正在克隆外部插件源到 custom_feeds/..."

# Passwall
git clone --depth 100 https://github.com/openwrt-passwall/openwrt-passwall.git custom_feeds/passwall
(cd custom_feeds/passwall && git checkout b93946a6f6984714db256f08537cdcdcd3523f25)

# Passwall Packages
git clone --depth 100 https://github.com/openwrt-passwall/openwrt-passwall-packages.git custom_feeds/passwall_packages
(cd custom_feeds/passwall_packages && git checkout 52a52b870661baac88e1912a19067c621580c8bc)

# Kwrt (op-packages)
git clone --depth 100 https://github.com/kiddin9/op-packages.git custom_feeds/kwrt
(cd custom_feeds/kwrt && git checkout 4384a37719f96b27e8a9f6d49ca02ce414757c2a)

# Argon Theme
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git custom_feeds/argon
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git custom_feeds/argon_config

# 2. 修改 feeds.conf.default，使用相对路径 (相对于 openwrt 根目录)
sed -i 's|^src-git.*passwall .*|src-link passwall custom_feeds/passwall|' feeds.conf.default
sed -i 's|^src-git.*passwall_packages .*|src-link passwall_packages custom_feeds/passwall_packages|' feeds.conf.default
sed -i 's|^src-git.*kwrt .*|src-link kwrt custom_feeds/kwrt|' feeds.conf.default
sed -i 's|^src-git.*argon .*|src-link argon custom_feeds/argon|' feeds.conf.default
sed -i 's|^src-git.*argon_config .*|src-link argon_config custom_feeds/argon_config|' feeds.conf.default

echo "  外部源锁定完成。"

echo ">>> CB-Shield-Q30 DIY Part 1 执行完毕"
