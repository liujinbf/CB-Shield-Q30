#!/bin/bash
# ============================================================
# CB-Shield-Q30 自定义脚本 Part 1
# 在 feeds 更新后、安装前执行
# 用途：添加自定义 feeds 源、修改 feed 配置
# ============================================================

echo ">>> CB-Shield-Q30 DIY Part 1 开始执行..."

# 1. 手动克隆并锁定外部 Feed 到兼容版本 (避开 Go 1.24 和 MbedTLS 3.x 冲突)
mkdir -p feeds
echo "  正在手动克隆并锁定外部插件源..."

# Passwall
git clone --depth 100 https://github.com/openwrt-passwall/openwrt-passwall.git feeds/passwall
(cd feeds/passwall && git checkout b93946a6f6984714db256f08537cdcdcd3523f25)

# Passwall Packages
git clone --depth 100 https://github.com/openwrt-passwall/openwrt-passwall-packages.git feeds/passwall_packages
(cd feeds/passwall_packages && git checkout 52a52b870661baac88e1912a19067c621580c8bc)

# Kwrt (op-packages)
git clone --depth 100 https://github.com/kiddin9/op-packages.git feeds/kwrt
(cd feeds/kwrt && git checkout 4384a37719f96b27e8a9f6d49ca02ce414757c2a)

# Argon Theme (确保即使上游源挂了也能拿到界面)
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git feeds/argon
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git feeds/argon_config

# 2. 修改 feeds.conf.default，将外部源转为本地链接 (src-link)
# 这样 scripts/feeds update 就不会尝试去覆盖我们手动锁定的版本
sed -i 's|^src-git.*passwall .*|src-link passwall feeds/passwall|' feeds.conf.default
sed -i 's|^src-git.*passwall_packages .*|src-link passwall_packages feeds/passwall_packages|' feeds.conf.default
sed -i 's|^src-git.*kwrt .*|src-link kwrt feeds/kwrt|' feeds.conf.default
sed -i 's|^src-git.*argon .*|src-link argon feeds/argon|' feeds.conf.default
sed -i 's|^src-git.*argon_config .*|src-link argon_config feeds/argon_config|' feeds.conf.default

echo "  外部源锁定完成。"

echo ">>> CB-Shield-Q30 DIY Part 1 执行完毕"
