#!/bin/bash
# =========================================================
# CB-Shield Pro (跨境卫士) - 核心定制脚本
# 适用硬件: Q30 / H3C NX30 Pro (MT7981)
# =========================================================

# 1. 基础系统设置
# ---------------------------------------------------------
# 修改默认 IP 为 192.168.10.1 (避开常见 IP 段，防止冲突)
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
# 修改默认主机名为 CB-Shield-Pro
sed -i 's/ImmortalWrt/CB-Shield-Pro/g' package/base-files/files/bin/config_generate
# 修改登录后的欢迎语 (Banner)
sed -i "s/OpenWrt /跨境卫士 v$(date +%Y.%m.%d) /g" package/base-files/files/etc/banner

# 2. UI 品牌化定制
# ---------------------------------------------------------
# 强制默认主题为 Design (来自 fanchmwrt 的精华 UI)
sed -i 's/luci-theme-bootstrap/luci-theme-design/g' feeds/luci/collections/luci/Makefile

# 自动化素材替换 (Logo 与 背景)
DESIGN_STATIC="feeds/luci/themes/luci-theme-design/htdocs/luci-static/design"
if [ -d "../images" ]; then
    # 替换左上角透明 Logo
    [ -f "../images/custom_logo.png" ] && cp -f ../images/custom_logo.png $DESIGN_STATIC/img/logo.png
    # 替换高清登录背景图
    [ -f "../images/custom_bg.jpg" ] && cp -f ../images/custom_bg.jpg $DESIGN_STATIC/img/bg.jpg
fi

# 3. 核心安全防护 (去指纹与防泄露)
# ---------------------------------------------------------
cat <<EOF >> package/base-files/files/etc/firewall.user
# [去指纹] 强制修改传出包 TTL 为 128 (模拟标准 Windows 10/11 系统)
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 128
# [防泄露] 强行屏蔽 WebRTC 常用探测端口 (3478, 19302)
iptables -A FORWARD -p udp --dport 3478 -j DROP
iptables -A FORWARD -p udp --dport 19302 -j DROP
# [传输优化] 锁定 MSS 为 1452，模拟真实住宅宽带流量特征
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
EOF

# 4. 硬件伪装 (WAN 口 MAC 随机化)
# ---------------------------------------------------------
# 模拟常见的 Realtek 网卡前缀，防止平台通过 OUI 识别路由器品牌
cat <<EOF >> package/base-files/files/etc/config/network
config event 'wan_mac_gen'
	option target 'wan'
	option action 'ifup'
	option script 'ip link set dev eth1 address 52:54:00:\$(hexdump -n 3 -e "3/1 \"%02x:\"" /dev/urandom | sed "s/:\$//")'
EOF

# 5. 可视化环境监测工具
# ---------------------------------------------------------
# 创建后台检测脚本
mkdir -p package/base-files/files/usr/bin
cat <<'EOF' > package/base-files/files/usr/bin/check_risk.sh
#!/bin/sh
# 调用风险库检测 IP 属性
IP_INFO=$(curl -s http://ip-api.com/json/?fields=61440)
IS_PROXY=$(echo $IP_INFO | grep -o '"proxy":true')
IS_HOSTING=$(echo $IP_INFO | grep -o '"hosting":true')
if [ -n "$IS_PROXY" ] || [ -n "$IS_HOSTING" ]; then
    echo "<span style='color:red;font-weight:bold;'>⚠️ 风险环境：检测到机房 IP 或代理特征，请勿操作账号！</span>" > /tmp/ip_risk_status
else
    echo "<span style='color:green;font-weight:bold;'>✅ 安全环境：原生住宅 IP，适合跨境运营。</span>" > /tmp/ip_risk_status
fi
EOF
chmod +x package/base-files/files/usr/bin/check_risk.sh

# 设置定时任务，每 5 分钟更新一次环境评分
echo "*/5 * * * * /usr/bin/check_risk.sh" >> package/base-files/files/etc/crontabs/root

# 6. LuCI 首页看板集成 (可视化展示)
# ---------------------------------------------------------
# 修改首页模板，插入“跨境环境安全检测”卡片
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

# 创建后端接口供前端调用
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

# 7. 清理指纹残留
sed -i 's/DISTRIB_REVISION=.*/DISTRIB_REVISION="CB-Shield-v2026"/g' package/base-files/files/etc/openwrt_release
