#!/bin/bash
set -e

echo ">>> CB-Shield-Q30 DIY Part 1 start"

# 准备外部 feeds
mkdir -p custom_feeds

clone_with_optional_pin() {
    local repo_url="$1"
    local repo_dir="$2"
    local pin_commit="$3"

    git clone --depth 1 "$repo_url" "$repo_dir"

    if [ -n "$pin_commit" ]; then
        if (cd "$repo_dir" && git fetch --depth 1 origin "$pin_commit" >/dev/null 2>&1 && git checkout -q "$pin_commit"); then
            echo "Pinned $repo_dir to $pin_commit"
        else
            echo "WARN: pin $pin_commit not available for $repo_dir, fallback to default branch HEAD"
        fi
    fi
}

clone_with_optional_pin \
    https://github.com/openwrt-passwall/openwrt-passwall.git \
    custom_feeds/passwall \
    b93946a6f6984714db256f08537cdcdcd3523f25

clone_with_optional_pin \
    https://github.com/openwrt-passwall/openwrt-passwall-packages.git \
    custom_feeds/passwall_packages \
    52a52b870661baac88e1912a19067c621580c8bc

clone_with_optional_pin \
    https://github.com/kiddin9/op-packages.git \
    custom_feeds/kwrt \
    4384a37719f96b27e8a9f6d49ca02ce414757c2a

git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git custom_feeds/argon
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git custom_feeds/argon_config

# 用本地 src-link 覆盖远程 feed，降低网络波动影响
sed -i 's|^src-git.*passwall .*|src-link passwall custom_feeds/passwall|' feeds.conf.default
sed -i 's|^src-git.*passwall_packages .*|src-link passwall_packages custom_feeds/passwall_packages|' feeds.conf.default
sed -i 's|^src-git.*kwrt .*|src-link kwrt custom_feeds/kwrt|' feeds.conf.default
sed -i 's|^src-git.*argon .*|src-link argon custom_feeds/argon|' feeds.conf.default
sed -i 's|^src-git.*argon_config .*|src-link argon_config custom_feeds/argon_config|' feeds.conf.default

echo ">>> CB-Shield-Q30 DIY Part 1 done"
