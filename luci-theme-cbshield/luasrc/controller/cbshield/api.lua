module("luci.controller.cbshield.api", package.seeall)

local json = require("luci.jsonc")
local sys = require("luci.sys")
local http = require("luci.http")

function index()
    -- API 端点注册
    entry({"admin", "cbshield", "api", "sysinfo"}, call("action_sysinfo")).leaf = true
    entry({"admin", "cbshield", "api", "riskstatus"}, call("action_riskstatus")).leaf = true
    entry({"admin", "cbshield", "api", "network"}, call("action_network")).leaf = true
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
-- 网络状态 API
-- ============================================================
function action_network()
    local data = {
        interfaces = {},
        vlans = {}
    }

    -- 获取网络接口信息
    local interfaces = {"vlan_office", "vlan_guest", "vlan_ecom", "wan"}
    for _, iface in ipairs(interfaces) do
        local info = {}
        info.name = iface
        info.up = (sys.exec("ubus call network.interface." .. iface .. " status 2>/dev/null | jsonfilter -e '@.up'") or ""):match("true") and true or false

        -- 获取 IP
        local ip = sys.exec("ubus call network.interface." .. iface .. " status 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address'")
        info.ip = ip and ip:gsub("%s+", "") or ""

        -- 获取流量统计
        local dev = sys.exec("ubus call network.interface." .. iface .. " status 2>/dev/null | jsonfilter -e '@.device'")
        if dev then
            dev = dev:gsub("%s+", "")
            local rx = tonumber(sys.exec("cat /sys/class/net/" .. dev .. "/statistics/rx_bytes 2>/dev/null")) or 0
            local tx = tonumber(sys.exec("cat /sys/class/net/" .. dev .. "/statistics/tx_bytes 2>/dev/null")) or 0
            info.rx_bytes = rx
            info.tx_bytes = tx
            info.rx_human = format_bytes(rx)
            info.tx_human = format_bytes(tx)
        end

        table.insert(data.interfaces, info)
    end

    -- 连接的客户端数量
    local arp = sys.exec("cat /proc/net/arp | grep -v 'IP address' | wc -l")
    data.total_clients = tonumber(arp) or 0

    http.prepare_content("application/json")
    http.write(json.stringify(data))
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
