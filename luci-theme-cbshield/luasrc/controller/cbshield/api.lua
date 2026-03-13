module("luci.controller.cbshield.api", package.seeall)

local json = require("luci.jsonc")
local sys = require("luci.sys")
local http = require("luci.http")

function index()
    -- API 端点注册
    entry({"admin", "cbshield", "api", "sysinfo"}, call("action_sysinfo")).leaf = true
    entry({"admin", "cbshield", "api", "riskstatus"}, call("action_riskstatus")).leaf = true
    entry({"admin", "cbshield", "api", "network"}, call("action_network")).leaf = true
    entry({"admin", "cbshield", "api", "toggle_shop"}, call("action_toggle_shop")).leaf = true
    entry({"admin", "cbshield", "api", "connections"}, call("action_connections")).leaf = true
end

-- ============================================================
-- 系统信息 API (CPU / 内存 / 运行时间)
-- ============================================================
function action_sysinfo()
    local data = {}

    -- CPU 使用率 (两次采样)
    local cpu1 = read_cpu_stat()
    sys.exec("sleep 1")
    local cpu2 = read_cpu_stat()

    if cpu1 and cpu2 then
        local idle_delta = cpu2.idle - cpu1.idle
        local total_delta = cpu2.total - cpu1.total
        if total_delta > 0 then
            data.cpu_usage = math.floor(((total_delta - idle_delta) / total_delta) * 100)
        else
            data.cpu_usage = 0
        end
    else
        data.cpu_usage = 0
    end

    -- 内存信息
    local meminfo = sys.exec("cat /proc/meminfo")
    if meminfo then
        local mem_total = tonumber(meminfo:match("MemTotal:%s+(%d+)")) or 0
        local mem_free = tonumber(meminfo:match("MemFree:%s+(%d+)")) or 0
        local mem_buffers = tonumber(meminfo:match("Buffers:%s+(%d+)")) or 0
        local mem_cached = tonumber(meminfo:match("Cached:%s+(%d+)")) or 0

        data.mem_total = math.floor(mem_total / 1024)  -- MB
        data.mem_used = math.floor((mem_total - mem_free - mem_buffers - mem_cached) / 1024)
        data.mem_usage = mem_total > 0 and math.floor(((mem_total - mem_free - mem_buffers - mem_cached) / mem_total) * 100) or 0
    end

    -- 运行时间
    local uptime_raw = sys.exec("cat /proc/uptime")
    if uptime_raw then
        local uptime_sec = tonumber(uptime_raw:match("^(%d+)")) or 0
        local days = math.floor(uptime_sec / 86400)
        local hours = math.floor((uptime_sec % 86400) / 3600)
        local mins = math.floor((uptime_sec % 3600) / 60)
        data.uptime = string.format("%d天 %d时 %d分", days, hours, mins)
        data.uptime_seconds = uptime_sec
    end

    -- 系统负载
    local loadavg = sys.exec("cat /proc/loadavg")
    if loadavg then
        data.load_1min, data.load_5min, data.load_15min = loadavg:match("^(%S+)%s+(%S+)%s+(%S+)")
    end

    -- 主机名
    data.hostname = sys.hostname() or "CB-Shield-Q30"

    http.prepare_content("application/json")
    http.write(json.stringify(data))
end

-- ============================================================
-- 风控状态 API
-- ============================================================
function action_riskstatus()
    local status_file = "/tmp/cb-riskcontrol.json"
    local data = {}

    local f = io.open(status_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        data = json.parse(content) or {status = "no_data"}
    else
        data = {status = "service_not_running"}
    end

    -- 添加服务运行状态
    local pid = sys.exec("pgrep -f 'cb-riskcontrol daemon'")
    data.service_running = (pid and pid ~= "") and true or false

    http.prepare_content("application/json")
    http.write(json.stringify(data))
end

-- ============================================================
-- 网络状态 API (更新以支持 5 个 Shop)
-- ============================================================
function action_network()
    local data = {
        interfaces = {},
        shops = {}
    }

    -- 1. 获取基础接口信息 (LAN / WAN)
    local base_ifaces = {"lan", "wan"}
    for _, iface in ipairs(base_ifaces) do
        local info = get_iface_info(iface)
        table.insert(data.interfaces, info)
    end

    -- 2. 获取 5 个隔离店铺环境信息
    for i = 1, 5 do
        local shop_id = "shop" .. i
        local info = get_iface_info(shop_id)
        
        -- 获取关联的 WiFi SSID 和 状态
        local wifi_id = "shop" .. i .. "_5g"
        info.ssid = sys.exec("uci -q get wireless." .. wifi_id .. ".ssid") or "N/A"
        info.wifi_enabled = (sys.exec("uci -q get wireless." .. wifi_id .. ".disabled") or "0") == "0"
        
        table.insert(data.shops, info)
    end

    -- 连接的客户端总数
    local arp = sys.exec("cat /proc/net/arp | grep -v 'IP address' | wc -l")
    data.total_clients = tonumber(arp) or 0

    http.prepare_content("application/json")
    http.write(json.stringify(data))
end

-- ============================================================
-- 店铺环境开关控制 API
-- ============================================================
function action_toggle_shop()
    local id = http.formvalue("id") -- shop1, shop2...
    local enable = http.formvalue("enable") == "1"
    
    if not id or not id:match("^shop%d$") then
        http.status(400, "Bad Request")
        return
    end

    local disabled_val = enable and "0" or "1"
    local wifi_id = id .. "_5g"

    -- 1. 修改网络接口状态
    sys.exec("uci set network." .. id .. ".disabled='" .. disabled_val .. "'")
    -- 2. 修改对应 DHCP 状态
    sys.exec("uci set dhcp." .. id .. ".ignore='" .. disabled_val .. "'")
    -- 3. 修改无线 SSID 状态
    sys.exec("uci set wireless." .. wifi_id .. ".disabled='" .. disabled_val .. "'")
    
    -- 提交并重启相关服务
    sys.exec("uci commit network; uci commit dhcp; uci commit wireless")
    
    -- 异步应用配置 (避免阻塞 API)
    sys.exec("/sbin/reload_config &")

    http.prepare_content("application/json")
    http.write(json.stringify({status = "success", enabled = enable}))
end

-- ============================================================
-- 辅助函数
-- ============================================================

-- 获取指定接口的详细信息
function get_iface_info(iface)
    local info = { name = iface }
    
    local status = sys.exec("ubus call network.interface." .. iface .. " status 2>/dev/null")
    if status and status ~= "" then
        local s = json.parse(status)
        info.up = s.up or false
        info.disabled = s.disabled or false
        
        if s["ipv4-address"] and s["ipv4-address"][1] then
            info.ip = s["ipv4-address"][1].address
        else
            info.ip = sys.exec("uci -q get network." .. iface .. ".ipaddr") or ""
        end

        if s.device then
            local dev = s.device
            local rx = tonumber(sys.exec("cat /sys/class/net/" .. dev .. "/statistics/rx_bytes 2>/dev/null")) or 0
            local tx = tonumber(sys.exec("cat /sys/class/net/" .. dev .. "/statistics/tx_bytes 2>/dev/null")) or 0
            info.rx_human = format_bytes(rx)
            info.tx_human = format_bytes(tx)
        end
    else
        -- 接口未启动时的备选显示
        info.up = false
        info.disabled = (sys.exec("uci -q get network." .. iface .. ".disabled") or "0") == "1"
        info.ip = sys.exec("uci -q get network." .. iface .. ".ipaddr") or ""
    end
    
    return info
end

-- ============================================================
-- 连接数 API
-- ============================================================
function action_connections()
    local data = {}

    local conntrack = sys.exec("cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null")
    local conntrack_max = sys.exec("cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null")

    data.active_connections = tonumber(conntrack) or 0
    data.max_connections = tonumber(conntrack_max) or 65536
    data.usage_percent = data.max_connections > 0 and math.floor((data.active_connections / data.max_connections) * 100) or 0

    http.prepare_content("application/json")
    http.write(json.stringify(data))
end

-- ============================================================
-- 辅助函数
-- ============================================================

-- 读取 CPU 统计
function read_cpu_stat()
    local stat = sys.exec("head -1 /proc/stat")
    if stat then
        local user, nice, system, idle, iowait, irq, softirq = stat:match(
            "cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)"
        )
        if user then
            local total = user + nice + system + idle + iowait + irq + softirq
            return {idle = tonumber(idle), total = total}
        end
    end
    return nil
end

-- 格式化字节
function format_bytes(bytes)
    if bytes >= 1073741824 then
        return string.format("%.2f GB", bytes / 1073741824)
    elseif bytes >= 1048576 then
        return string.format("%.2f MB", bytes / 1048576)
    elseif bytes >= 1024 then
        return string.format("%.2f KB", bytes / 1024)
    else
        return string.format("%d B", bytes)
    end
end
