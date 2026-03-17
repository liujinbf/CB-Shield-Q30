#!/bin/bash
set -e

echo ">>> CB-Shield-Q30 DIY Part 1 start"

# 准备外部 feeds
mkdir -p custom_feeds

git clone --depth 100 https://github.com/openwrt-passwall/openwrt-passwall.git custom_feeds/passwall
(cd custom_feeds/passwall && git checkout b93946a6f6984714db256f08537cdcdcd3523f25)

git clone --depth 100 https://github.com/openwrt-passwall/openwrt-passwall-packages.git custom_feeds/passwall_packages
(cd custom_feeds/passwall_packages && git checkout 52a52b870661baac88e1912a19067c621580c8bc)

git clone --depth 100 https://github.com/kiddin9/op-packages.git custom_feeds/kwrt
(cd custom_feeds/kwrt && git checkout 4384a37719f96b27e8a9f6d49ca02ce414757c2a)

git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git custom_feeds/argon
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git custom_feeds/argon_config

# 替换 feeds.conf.default 中对应源为本地 src-link
sed -i 's|^src-git.*passwall .*|src-link passwall custom_feeds/passwall|' feeds.conf.default
sed -i 's|^src-git.*passwall_packages .*|src-link passwall_packages custom_feeds/passwall_packages|' feeds.conf.default
sed -i 's|^src-git.*kwrt .*|src-link kwrt custom_feeds/kwrt|' feeds.conf.default
sed -i 's|^src-git.*argon .*|src-link argon custom_feeds/argon|' feeds.conf.default
sed -i 's|^src-git.*argon_config .*|src-link argon_config custom_feeds/argon_config|' feeds.conf.default

echo ">>> CB-Shield-Q30 DIY Part 1 done"
