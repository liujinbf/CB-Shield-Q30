#!/bin/bash
# =========================================================
# CB-Shield Pro (跨境卫士) - V2 终极优化脚本
# 功能：深度协议栈伪装、IPv6 物理屏蔽、全局流量锁、品牌化定制
# =========================================================

# 1. 基础系统与品牌设置
# ---------------------------------------------------------
# 修改默认 IP 为 192.168.10.1 (避开常见 IP 段)
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
# 修改默认主机名为 CB-Shield-Pro
sed -i 's/ImmortalWrt/CB-Shield-Pro/g' package/base-files/files/bin/config_generate
# 修改登录后的欢迎语
sed -i "s/OpenWrt /跨境卫士 v$(date +%Y.%m.%d) /g" package/base-files/files/etc/banner

# 强制默认主题为 Design (由于你使用了 kenzok8 源，该主题会自动包含)
sed -i 's/luci-theme-bootstrap/luci-theme-design/g' feeds/luci/collections/luci/Makefile

# --- 【核心修正】：针对 kenzok8 仓库的素材替换路径 ---
DESIGN_STATIC="feeds/kenzok8/luci-theme-design/htdocs/luci-static/design"
if [ -d "../images" ]; then
    # 替换左上角透明 Logo
    [ -f "../images/custom_logo.png" ] && cp -f ../images/custom_logo.png $DESIGN_STATIC/img/logo.png
    # 替换高清登录背景图
    [ -f "../images/custom_bg.jpg" ] && cp -f ../images/custom_bg.jpg $DESIGN_STATIC/img/bg.jpg
fi

# 2. 核心安全防护 (去指纹与防泄露)
# ---------------------------------------------------------
cat <<EOF >> package/base-files/files/etc/firewall.user
# [去指纹] 强制修改 TTL 为 128 (模拟标准 Windows 10/11)
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 128
# [防泄露] 屏蔽 WebRTC 探测端口
iptables -A FORWARD -p udp --dport 3478 -j DROP
iptables -A FORWARD -p udp --dport 19302 -j DROP
# [传输优化] 锁定 MSS 为 1452，消除隧道传输特征
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
EOF

# 3. 协议栈深度伪装与 IPv6 屏蔽
# ---------------------------------------------------------
# 禁用 IPv6 以彻底杜绝地理位置泄露
sed -i 's/option disable_ipv6 .*/option disable_ipv6 1/g' package/base-files/files/etc/config/network
cat <<EOF >> package/base-files/files/etc/sysctl.conf
# 模拟 Windows TCP 堆栈特征，关闭 Linux 时间戳特征
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_window_scaling = 1
# 彻底关闭 IPv6 协议栈
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

# 4. 硬件特征混淆 (随机 MAC 地址)
# ---------------------------------------------------------
# 随机化 WAN 口 MAC，防止平台通过 OUI 识别路由器品牌
cat <<EOF >> package/base-files/files/etc/config/network
config event 'wan_mac_gen'
	option target 'wan'
	option action 'ifup'
	option script 'ip link set dev eth1 address 52:54:00:\$(hexdump -n 3 -e "3/1 \"%02x:\"" /dev/urandom | sed "s/:\$//")'
EOF

# 5. 环境监测与可视化看板
# ---------------------------------------------------------
mkdir -p package/base-files/files/usr/bin
cat <<'EOF' > package/base-files/files/usr/bin/check_risk.sh
#!/bin/sh
# 调用 IP-API 检测当前环境纯净度
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
# 每 5 分钟更新一次安全状态
echo "*/5 * * * * /usr/bin/check_risk.sh" >> package/base-files/files/etc/crontabs/root

# 首页可视化看板注入
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

# 注入后端 API 接口
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

# 6. 全局流量锁 (Kill Switch)
# ---------------------------------------------------------
# 设置固件修订版本
sed -i 's/DISTRIB_REVISION=.*/DISTRIB_REVISION="CB-Shield-Pro-V2"/g' package/base-files/files/etc/openwrt_release

# 守卫进程：防止节点掉线后真实 IP 泄露
mkdir -p package/base-files/files/usr/bin
cat <<'EOF' > package/base-files/files/usr/bin/proxy_watchdog.sh
#!/bin/sh
while true; do
    if ! curl -I -s --connect-timeout 3 https://www.google.com > /dev/null; then
        # 如果掉线，立即切断转发流量
        iptables -I FORWARD -p tcp -j REJECT
        iptables -I FORWARD -p udp -j REJECT
        echo "<span style='color:red;font-weight:bold;'>🚫 保护性断网：节点已掉线，流量已拦截！</span>" > /tmp/ip_risk_status
    else
        # 恢复连接后释放封锁
        iptables -D FORWARD -p tcp -j REJECT 2>/dev/null
        iptables -D FORWARD -p udp -j REJECT 2>/dev/null
    fi
    sleep 10
done
EOF
chmod +x package/base-files/files/usr/bin/proxy_watchdog.sh
# 开机自启守卫进程
sed -i '/exit 0/i /usr/bin/proxy_watchdog.sh &' package/base-files/files/etc/rc.local
