#!/bin/bash
# ============================================================
# CB-Shield-Q30 自定义脚本 Part 1
# 在 feeds 更新后、安装前执行
# 用途：添加自定义 feeds 源、修改 feed 配置
# ============================================================

echo ">>> CB-Shield-Q30 DIY Part 1 开始执行..."

# 添加自定义 Passwall 源（如果 feeds.conf.default 中未包含）
# grep -q "passwall" feeds.conf.default || {
#     echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main" >> feeds.conf.default
#     echo "src-git passwall https://github.com/xiaorouji/openwrt-passwall.git;main" >> feeds.conf.default
# }

echo ">>> CB-Shield-Q30 DIY Part 1 执行完毕"
