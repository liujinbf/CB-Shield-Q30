#!/bin/bash
# =========================================================
# CB-Shield Pro (跨境卫士) - 全球自动时区优化版
# =========================================================

# 1. 基础系统与品牌设置
# ---------------------------------------------------------
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/CB-Shield-Pro/g' package/base-files/files/bin/config_generate
sed -i "s/OpenWrt /跨境卫士 v$(date +%Y.%m.%d) /g" package/base-files/files/etc/banner

# 强制默认主题为 Design
sed -i 's/luci-theme-bootstrap/luci-theme-design/g' feeds/luci/collections/luci/Makefile

# 自动化素材替换 (针对 kenzok8 仓库路径优化)
DESIGN_STATIC="feeds/kenzok8/luci-theme-design/htdocs/luci-static/design"
if [ -d "images" ]; then
    [ -f "images/custom_logo.png" ] && cp -f images/custom_logo.png $DESIGN_STATIC/img/logo.png
    [ -f "images/custom_bg.jpg" ] && cp -f images/custom_bg.jpg $DESIGN_STATIC/img/bg.jpg
fi

# 2. 【核心新增】全球 IP 自动时区同步脚本
# ---------------------------------------------------------
mkdir -p package/base-files/files/usr/bin
cat <<'EOF' > package/base-files/files/usr/bin/sync_timezone.sh
#!/bin/sh
# 获取当前节点的时区信息
IP_JSON=$(curl -s http://ip-api.com/json/?fields=timezone)
NEW_ZONE=$(echo $IP_JSON | grep -o '"timezone":"[^"]*' | cut -d'"' -f4)

if [ -n "$NEW_ZONE" ]; then
    # 使用 uci 设置系统时区
    uci set system.@system[0].zonename="$NEW_ZONE"
    uci set system.@system[0].timezone="GMT0" # zonename 优先级高，此行作为占位
    uci commit system
    /etc/init.d/system reload
    echo "时区已自动同步为: $NEW_ZONE"
fi
EOF
chmod +x package/base-files/files/usr/bin/sync_timezone.sh

# 3. 核心安全防护 (去指纹与防泄露)
# ---------------------------------------------------------
cat <<EOF >> package/base-files/files/etc/firewall.user
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 128
iptables -A FORWARD -p udp --dport 3478 -j DROP
iptables -A FORWARD -p udp --dport 19302 -j DROP
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
EOF

# 禁用 IPv6、开启 BBR 加速并优化 TCP 特征
sed -i 's/option disable_ipv6 .*/option disable_ipv6 1/g' package/base-files/files/etc/config/network
echo "net.ipv4.tcp_timestamps = 0" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> package/base-files/files/etc/sysctl.conf

# 4. 环境监测、流量锁与时区联动
# ---------------------------------------------------------
cat <<'EOF' > package/base-files/files/usr/bin/check_risk.sh
#!/bin/sh
# 同时进行风险检测和时区同步
/usr/bin/sync_timezone.sh &
IP_INFO=$(curl -s http://ip-api.com/json/?fields=61440)
IS_PROXY=$(echo $IP_INFO | grep -o '"proxy":true')
IS_HOSTING=$(echo $IP_INFO | grep -o '"hosting":true')
if [ -n "$IS_PROXY" ] || [ -n "$IS_HOSTING" ]; then
    echo "<span style='color:red;font-weight:bold;'>⚠️ 风险环境：机房IP，请检查节点！</span>" > /tmp/ip_risk_status
else
    echo "<span style='color:green;font-weight:bold;'>✅ 安全环境：原生住宅IP。</span>" > /tmp/ip_risk_status
fi
EOF
chmod +x package/base-files/files/usr/bin/check_risk.sh
echo "*/10 * * * * /usr/bin/check_risk.sh" >> package/base-files/files/etc/crontabs/root

# 流量锁 (Kill Switch) 逻辑
cat <<'EOF' > package/base-files/files/usr/bin/proxy_watchdog.sh
#!/bin/sh
while true; do
    if ! curl -I -s --connect-timeout 3 https://www.google.com > /dev/null; then
        iptables -I FORWARD -p tcp -j REJECT
        iptables -I FORWARD -p udp -j REJECT
        echo "<span style='color:red;font-weight:bold;'>🚫 保护性断网：节点已掉线。</span>" > /tmp/ip_risk_status
    else
        iptables -D FORWARD -p tcp -j REJECT 2>/dev/null
        iptables -D FORWARD -p udp -j REJECT 2>/dev/null
    fi
    sleep 10
done
EOF
chmod +x package/base-files/files/usr/bin/proxy_watchdog.sh
sed -i '/exit 0/i /usr/bin/proxy_watchdog.sh &' package/base-files/files/etc/rc.local

# 5. UI 看板注入 (LuCI 首页)
# ---------------------------------------------------------
INDEX_HTML="feeds/luci/modules/luci-mod-status/luasrc/view/admin_status/index.htm"
sed -i '/<%:System%>/i \
<fieldset class="cbi-section"> \
	<legend>🛡️ 跨境卫士：风险监测</legend> \
	<div class="cbi-section-node"> \
		<table class="cbi-section-table"> \
			<tr class="cbi-section-table-row"> \
				<td class="cbi-section-table-cell" id="ip_risk_display" style="padding:15px; font-size:1.1em;">评估中...</td> \
			</tr> \
		</table> \
	</div> \
</fieldset> \
<script type="text/javascript"> \
	XHR.poll(5, "<%=luci.dispatcher.build_url("admin/status/ip_status")%>", null, \
		function(x, data) { \
			var d = document.getElementById("ip_risk_display"); \
			if (d && data) { d.innerHTML = data.status; } \
		} \
	); \
</script>' $INDEX_HTML

mkdir -p package/base-files/files/usr/lib/lua/luci/controller/admin/
cat <<EOF > package/base-files/files/usr/lib/lua/luci/controller/admin/custom_status.lua
module("luci.controller.admin.custom_status", package.seeall)
function index()
    entry({"admin", "status", "ip_status"}, call("get_ip_status"), nil, 60).leaf = true
end
function get_ip_status()
    local f = io.open("/tmp/ip_risk_status", "r")
    local s = f and f:read("*all") or "初始化中..."
    if f then f:close() end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = s})
end
EOF

sed -i 's/DISTRIB_REVISION=.*/DISTRIB_REVISION="CB-Shield-Pro-V2"/g' package/base-files/files/etc/openwrt_release
