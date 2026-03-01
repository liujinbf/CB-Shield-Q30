#!/bin/bash
# =========================================================
# CB-Shield Pro (跨境卫士) - V2 终极优化脚本
# 功能：深度协议栈伪装、IPv6 物理屏蔽、全局流量锁
# =========================================================

# 1. 基础系统与品牌设置
# ---------------------------------------------------------
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/CB-Shield-Pro/g' package/base-files/files/bin/config_generate
sed -i "s/OpenWrt /跨境卫士 v$(date +%Y.%m.%d) /g" package/base-files/files/etc/banner

# 强制默认主题为 Design
sed -i 's/luci-theme-bootstrap/luci-theme-design/g' feeds/luci/collections/luci/Makefile

# 自动化素材替换 (Logo 与 背景)
DESIGN_STATIC="feeds/luci/themes/luci-theme-design/htdocs/luci-static/design"
if [ -d "../images" ]; then
    [ -f "../images/custom_logo.png" ] && cp -f ../images/custom_logo.png $DESIGN_STATIC/img/logo.png
    [ -f "../images/custom_bg.jpg" ] && cp -f ../images/custom_bg.jpg $DESIGN_STATIC/img/bg.jpg
fi

# 2. 核心安全防护 (去指纹与防泄露)
# ---------------------------------------------------------
cat <<EOF >> package/base-files/files/etc/firewall.user
# [去指纹] 强制修改 TTL 为 128 (模拟标准 Windows)
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 128
# [防泄露] 屏蔽 WebRTC 探测端口
iptables -A FORWARD -p udp --dport 3478 -j DROP
iptables -A FORWARD -p udp --dport 19302 -j DROP
# [传输优化] 锁定 MSS 为 1452
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
EOF

# 3. 【V2 新增】协议栈深度伪装与 IPv6 屏蔽
# ---------------------------------------------------------
# 禁用 IPv6 以彻底杜绝地理位置泄露
sed -i 's/option disable_ipv6 .*/option disable_ipv6 1/g' package/base-files/files/etc/config/network
cat <<EOF >> package/base-files/files/etc/sysctl.conf
# 模拟 Windows TCP 堆栈特征，关闭 Linux 时间戳特征
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_window_scaling = 1
# 彻底关闭 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

# 4. 【V2 新增】硬件特征混淆 (随机 MAC 与 DHCP 伪装)
# ---------------------------------------------------------
# 随机化 WAN 口 MAC，并模拟 Windows DHCP 请求特征
cat <<EOF >> package/base-files/files/etc/config/network
config event 'wan_mac_gen'
	option target 'wan'
	option action 'ifup'
	option script 'ip link set dev eth1 address 52:54:00:\$(hexdump -n 3 -e "3/1 \"%02x:\"" /dev/urandom | sed "s/:\$//")'
EOF

# 5. 环境监测与看板集成
# ---------------------------------------------------------
mkdir -p package/base-files/files/usr/bin
cat <<'EOF' > package/base-files/files/usr/bin/check_risk.sh
#!/bin/sh
# 调用风险库检测 IP 属性
IP_INFO=$(curl -s http://ip-api.com/json/?fields=61440)
IS_PROXY=$(echo $IP_INFO | grep -o '"proxy":true')
IS_HOSTING=$(echo $IP_INFO | grep -o '"hosting":true')
if [ -n "$IS_PROXY" ] || [ -n "$IS_HOSTING" ]; then
    echo "<span style='color:red;font-weight:bold;'>⚠️ 风险环境：检测到机房 IP，请勿操作账号！</span>" > /tmp/ip_risk_status
else
    echo "<span style='color:green;font-weight:bold;'>✅ 安全环境：原生住宅 IP，适合运营。</span>" > /tmp/ip_risk_status
fi
EOF
chmod +x package/base-files/files/usr/bin/check_risk.sh
echo "*/5 * * * * /usr/bin/check_risk.sh" >> package/base-files/files/etc/crontabs/root

# 首页可视化卡片注入逻辑 (LuCI 看板)
INDEX_HTML="feeds/luci/modules/luci-mod-status/luasrc/view/admin_status/index.htm"
sed -i '/<%:System%>/i \
<fieldset class="cbi-section"> \
	<legend>🛡️ 跨境卫士：环境安全检测</legend> \
	<div class="cbi-section-node"> \
		<table class="cbi-section-table"> \
			<tr class="cbi-section-table-row"> \
				<td class="cbi-section-table-cell" id="ip_risk_display" style="padding:15px; font-size:1.1em;"> \
					正在实时评估当前跨境环境安全性... \
				</td> \
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

# 后端接口 API
mkdir -p package/base-files/files/usr/lib/lua/luci/controller/admin/
cat <<EOF > package/base-files/files/usr/lib/lua/luci/controller/admin/custom_status.lua
module("luci.controller.admin.custom_status", package.seeall)
function index()
    entry({"admin", "status", "ip_status"}, call("get_ip_status"), nil, 60).leaf = true
end
function get_ip_status()
    local f = io.open("/tmp/ip_risk_status", "r")
    local s = f and f:read("*all") or "系统初始化中..."
    if f then f:close() end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = s})
end
EOF

# 终极指纹清理
sed -i 's/DISTRIB_REVISION=.*/DISTRIB_REVISION="CB-Shield-Pro-V2"/g' package/base-files/files/etc/openwrt_release
