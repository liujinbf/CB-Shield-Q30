#!/bin/bash
# 1. 添加 PassWall 核心源
echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
echo 'src-git passwall_luci https://github.com/xiaorouji/openwrt-passwall-luci' >>feeds.conf.default

# 2. 拉取 fanchmwrt 的专属 Design 主题
git clone https://github.com/fanchmwrt/luci-theme-design.git package/luci-theme-design

# 3. 添加额外依赖包源
git clone https://github.com/kenzok8/openwrt-packages.git package/openwrt-packages
