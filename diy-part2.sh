#!/bin/bash
# =========================================================
# CB-Shield Pro (跨境卫士) - V2.1 终极版
# =========================================================

# 1. 基础系统与品牌设置 (含 IP 与 密码修改)
# ---------------------------------------------------------
# 修改默认管理 IP 为 192.168.6.1
sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate
# 修改默认主机名为 CB-Shield-Pro
sed -i 's/ImmortalWrt/CB-Shield-Pro/g' package/base-files/files/bin/config_generate
# 设置默认登录密码为 root (加密 hash 为 $1$V4UetPzk$CY6SVvI3Nzn8vVBDpc9Zq0)
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CY6SVvI3Nzn8vVBDpc9Zq0:0:99999:7:::/g' package/base-files/files/etc/shadow

# 自动化素材替换 (Logo 与 背景)
DESIGN_STATIC="feeds/kenzok8/luci-theme-design/htdocs/luci-static/design"
if [ -d "images" ]; then
    [ -f "images/custom_logo.png" ] && cp -f images/custom_logo.png $DESIGN_STATIC/img/logo.png
    [ -f "images/custom_bg.jpg" ] && cp -f images/custom_bg.jpg $DESIGN_STATIC/img/bg.jpg
fi

# 2. 核心安全防护 (去指纹与防泄露)
# ---------------------------------------------------------
cat <<EOF >> package/base-files/files/etc/firewall.user
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 128
iptables -A FORWARD -p udp --dport 3478 -j DROP
iptables -A FORWARD -p udp --dport 19302 -j DROP
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
EOF

# 禁用 IPv6、开启 BBR 加速并伪装 TCP 栈
sed -i 's/option disable_ipv6 .*/option disable_ipv6 1/g' package/base-files/files/etc/config/network
echo "net.ipv4.tcp_timestamps = 0" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> package/base-files/files/etc/sysctl.conf
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> package/base-files/files/etc/sysctl.conf

# 3. 风险监测、全球时区同步与流量锁
# ---------------------------------------------------------
mkdir -p package/base-files/files/usr/bin
# 风险监测 + 时区同步脚本
cat <<'EOF' > package/base-files/files/usr/bin/check_risk.sh
#!/bin/sh
IP_JSON=$(curl -s http://ip-api.com/json/?fields=61440,timezone)
NEW_ZONE=$(echo $IP_JSON | grep -o '"timezone":"[^"]*' | cut -d'"' -f4)
if [ -n "$NEW_ZONE" ]; then
    uci set system.@system[0].zonename="$NEW_ZONE" && uci commit system && /etc/init.d/system reload
fi
IS_PROXY=$(echo $IP_JSON | grep -o '"proxy":true')
if [ -n "$IS_PROXY" ]; then
    echo "<span style='color:red;font-weight:bold;'>⚠️ 风险环境：机房IP，禁止操作！</span>" > /tmp/ip_risk_status
else
    echo "<span style='color:green;font-weight:bold;'>✅ 安全环境：原生住宅IP。</span>" > /tmp/ip_risk_status
fi
EOF
chmod +x package/base-files/files/usr/bin/check_risk.sh
echo "*/10 * * * * /usr/bin/check_risk.sh" >> package/base-files/files/etc/crontabs/root

# 流量锁 (Kill Switch)
cat <<'EOF' > package/base-files/files/usr/bin/proxy_watchdog.sh
#!/bin/sh
while true; do
    if ! curl -I -s --connect-timeout 3 https://www.google.com > /dev/null; then
        iptables -I FORWARD -p tcp -j REJECT
        iptables -I FORWARD -p udp -j REJECT
        echo "<span style='color:red;font-weight:bold;'>🚫 已断网：节点掉线保护中。</span>" > /tmp/ip_risk_status
    else
        iptables -D FORWARD -p tcp -j REJECT 2>/dev/null
        iptables -D FORWARD -p udp -j REJECT 2>/dev/null
    fi
    sleep 10
done
EOF
chmod +x package/base-files/files/usr/bin/proxy_watchdog.sh
sed -i '/exit 0/i /usr/bin/proxy_watchdog.sh &' package/base-files/files/etc/rc.local

# 4. UI 看板注入与“百科弹窗”逻辑
# ---------------------------------------------------------
INDEX_HTML="feeds/luci/modules/luci-mod-status/luasrc/view/admin_status/index.htm"
# 注入弹窗 CSS 和 HTML
sed -i '/<%:System%>/i \
<style> \
	.shield-help-btn { cursor:pointer; color:#007bff; text-decoration:underline; font-size:0.9em; margin-left:10px; } \
	.shield-modal { display:none; position:fixed; z-index:1000; left:0; top:0; width:100%; height:100%; background-color:rgba(0,0,0,0.5); } \
	.shield-modal-content { background-color:#fff; margin:15% auto; padding:20px; border-radius:8px; width:85%; max-width:450px; line-height:1.6; color:#333; } \
</style> \
<fieldset class="cbi-section"> \
	<legend>🛡️ 跨境卫士：风险监测</legend> \
	<div class="cbi-section-node"> \
		<table class="cbi-section-table"> \
			<tr class="cbi-section-table-row"> \
				<td class="cbi-section-table-cell" style="padding:15px;"> \
					<span id="ip_risk_display">评估中...</span> \
					<span class="shield-help-btn" onclick="document.getElementById(\"shieldModal\").style.display=\"block\"">为什么？</span> \
				</td> \
			</tr> \
		</table> \
	</div> \
</fieldset> \
<div id="shieldModal" class="shield-modal" onclick="this.style.display=\"none\""> \
	<div class="shield-modal-content" onclick="event.stopPropagation()"> \
		<h3>💡 跨境指纹百科</h3> \
		<p><b>TTL 128:</b> 模拟真实 Windows 环境，避开平台对路由器的探测。</p> \
		<p><b>WebRTC 屏蔽:</b> 防止浏览器泄露您的中国真实内网 IP。</p> \
		<p><b>流量锁:</b> 节点一旦掉线即断开物理连接，确保绝不直连。</p> \
		<hr> \
		<p style="text-align:center;"><small>更多深度知识请下载附赠的 Anki 牌组。</small></p> \
	</div> \
</div> \
<script type="text/javascript"> \
	XHR.poll(5, "<%=luci.dispatcher.build_url("admin/status/ip_status")%>", null, \
		function(x, data) { \
			var d = document.getElementById("ip_risk_display"); \
			if (d && data) { d.innerHTML = data.status; } \
		} \
	); \
</script>' $INDEX_HTML

# 注入后端 API
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

sed -i 's/DISTRIB_REVISION=.*/DISTRIB_REVISION="CB-Shield-Pro-V2.1"/g' package/base-files/files/etc/openwrt_release
