#!/bin/bash
# 1. 添加 PassWall 核心源
echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
echo 'src-git passwall_luci https://github.com/xiaorouji/openwrt-passwall-luci' >>feeds.conf.default

# 2. 添加 Design 主题源 (改为 feed 方式)
echo 'src-git design https://github.com/fanchmwrt/luci-theme-design' >>feeds.conf.default

# 3. 添加额外依赖包源 (改为 feed 方式)
echo 'src-git kenzok8 https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default
