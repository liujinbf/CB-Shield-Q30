#!/bin/bash
# 1. 修改默认 IP 为 192.168.10.1
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# 2. 修改固件名称与欢迎语
sed -i 's/ImmortalWrt/CB-Shield-Pro/g' package/base-files/files/bin/config_generate
sed -i "s/OpenWrt /跨境卫士 v$(date +%Y.%m.%d) /g" package/base-files/files/etc/banner

# 3. 强制默认主题为 Design
sed -i 's/luci-theme-bootstrap/luci-theme-design/g' feeds/luci/collections/luci/Makefile

# 4. 【核心防关联】TCP/IP 指纹模拟 Windows 10/11
cat <<EOF >> package/base-files/files/etc/firewall.user
# 强制修改所有传出包的 TTL 为 128 (Windows 标准值)
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 128
# 屏蔽 WebRTC 常见泄漏端口
iptables -A FORWARD -p udp --dport 3478 -j DROP
iptables -A FORWARD -p udp --dport 19302 -j DROP
EOF

# 5. 注入“IP 风险检测”脚本到首页看板
mkdir -p package/base-files/files/usr/bin
cat <<'EOF' > package/base-files/files/usr/bin/check_risk.sh
#!/bin/sh
IP_INFO=$(curl -s http://ip-api.com/json/?fields=61440)
IS_PROXY=$(echo $IP_INFO | grep -o '"proxy":true')
IS_HOSTING=$(echo $IP_INFO | grep -o '"hosting":true')
if [ -n "$IS_PROXY" ] || [ -n "$IS_HOSTING" ]; then
    echo "<span style='color:red;font-weight:bold;'>⚠️ 风险环境：检测到机房 IP，请勿注册账号！</span>" > /tmp/ip_risk_status
else
    echo "<span style='color:green;font-weight:bold;'>✅ 安全环境：原生住宅 IP，适合运营。</span>" > /tmp/ip_risk_status
fi
EOF
chmod +x package/base-files/files/usr/bin/check_risk.sh
echo "*/5 * * * * /usr/bin/check_risk.sh" >> package/base-files/files/etc/crontabs/root

# 6. 素材替换逻辑 (Logo 与 背景)
DESIGN_STATIC="feeds/luci/themes/luci-theme-design/htdocs/luci-static/design"
if [ -d "../images" ]; then
    [ -f "../images/custom_logo.png" ] && cp -f ../images/custom_logo.png $DESIGN_STATIC/img/logo.png
    [ -f "../images/custom_bg.jpg" ] && cp -f ../images/custom_bg.jpg $DESIGN_STATIC/img/bg.jpg
fi
