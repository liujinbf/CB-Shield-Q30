module("luci.controller.cbshield.api", package.seeall)

local http = require("luci.http")
local json = require("luci.jsonc")
local sys = require("luci.sys")

function index()
    entry({"admin", "cbshield", "api", "sysinfo"}, call("action_sysinfo")).leaf = true
    entry({"admin", "cbshield", "api", "riskstatus"}, call("action_riskstatus")).leaf = true
    entry({"admin", "cbshield", "api", "runcheck"}, call("action_runcheck")).leaf = true
    entry({"admin", "cbshield", "api", "network"}, call("action_network")).leaf = true
    entry({"admin", "cbshield", "api", "connections"}, call("action_connections")).leaf = true
    entry({"admin", "cbshield", "api", "health"}, call("action_health")).leaf = true
    entry({"admin", "cbshield", "api", "ha_status"}, call("action_ha_status")).leaf = true
    entry({"admin", "cbshield", "api", "dns_status"}, call("action_dns_status")).leaf = true
    entry({"admin", "cbshield", "api", "events"}, call("action_events")).leaf = true
    entry({"admin", "cbshield", "api", "wizard_status"}, call("action_wizard_status")).leaf = true
    entry({"admin", "cbshield", "api", "wizard_apply"}, call("action_wizard_apply")).leaf = true
    entry({"admin", "cbshield", "api", "upgrade_check"}, call("action_upgrade_check")).leaf = true
end

local function trim(value)
    if not value then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shq(value)
    value = tostring(value or "")
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function write_json(data)
    http.prepare_content("application/json")
    http.write(json.stringify(data))
end

local function parse_json_file(path, default_data)
    local handle = io.open(path, "r")
    if not handle then
        return default_data
    end

    local content = handle:read("*a")
    handle:close()
    return json.parse(content) or default_data
end

local function request_method()
    return (http.getenv("REQUEST_METHOD") or "GET"):upper()
end

local function require_post()
    if request_method() == "POST" then
        return true
    end

    http.status(405, "Method Not Allowed")
    write_json({ status = "method_not_allowed" })
    return false
end

local function service_exists(name)
    return sys.call("test -x /etc/init.d/" .. name) == 0
end

local function service_running(name)
    if not service_exists(name) then
        return false
    end
    return sys.call("/etc/init.d/" .. name .. " status >/dev/null 2>&1") == 0
end

local function find_proxy_service()
    if service_exists("openclash") then
        return "openclash"
    end
    if service_exists("passwall") then
        return "passwall"
    end
    return ""
end

local function read_cpu_stat()
    local stat = sys.exec("head -1 /proc/stat")
    if stat and stat ~= "" then
        local user, nice, systemv, idle, iowait, irq, softirq = stat:match(
            "cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)"
        )
        if user then
            local total = tonumber(user) + tonumber(nice) + tonumber(systemv) + tonumber(idle) +
                tonumber(iowait) + tonumber(irq) + tonumber(softirq)
            return { idle = tonumber(idle), total = total }
        end
    end
    return nil
end

local function format_bytes(bytes)
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

local function get_iface_info(iface)
    local info = { name = iface }
    local status = sys.exec("ubus call network.interface." .. iface .. " status 2>/dev/null")

    if status and status ~= "" then
        local parsed = json.parse(status) or {}
        info.up = parsed.up or false
        info.disabled = parsed.disabled or false

        if parsed["ipv4-address"] and parsed["ipv4-address"][1] then
            info.ip = parsed["ipv4-address"][1].address or ""
        else
            info.ip = trim(sys.exec("uci -q get network." .. iface .. ".ipaddr"))
        end

        local device = parsed.device or parsed.l3_device
        if device then
            local rx = tonumber(trim(sys.exec("cat /sys/class/net/" .. device .. "/statistics/rx_bytes 2>/dev/null"))) or 0
            local tx = tonumber(trim(sys.exec("cat /sys/class/net/" .. device .. "/statistics/tx_bytes 2>/dev/null"))) or 0
            info.device = device
            info.rx_human = format_bytes(rx)
            info.tx_human = format_bytes(tx)
        else
            info.rx_human = "0 B"
            info.tx_human = "0 B"
        end
    else
        info.up = false
        info.disabled = trim(sys.exec("uci -q get network." .. iface .. ".disabled")) == "1"
        info.ip = trim(sys.exec("uci -q get network." .. iface .. ".ipaddr"))
        info.rx_human = "0 B"
        info.tx_human = "0 B"
    end

    return info
end

local function get_wifi_info(section, title, band)
    local ssid = trim(sys.exec("uci -q get wireless." .. section .. ".ssid"))
    local network = trim(sys.exec("uci -q get wireless." .. section .. ".network"))
    local encryption = trim(sys.exec("uci -q get wireless." .. section .. ".encryption"))
    local disabled = trim(sys.exec("uci -q get wireless." .. section .. ".disabled"))

    if ssid == "" then
        ssid = "未配置"
    end
    if network == "" then
        network = "lan"
    end
    if encryption == "" then
        encryption = "unknown"
    end

    return {
        id = section,
        title = title,
        band = band,
        ssid = ssid,
        network = network,
        encryption = encryption,
        enabled = disabled ~= "1"
    }
end

local function get_proxy_state()
    local service = find_proxy_service()
    if service == "" then
        return {
            present = false,
            service = "none",
            running = false
        }
    end

    return {
        present = true,
        service = service,
        running = service_running(service)
    }
end

function action_sysinfo()
    local data = {}

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

    local meminfo = sys.exec("cat /proc/meminfo")
    if meminfo and meminfo ~= "" then
        local mem_total = tonumber(meminfo:match("MemTotal:%s+(%d+)")) or 0
        local mem_free = tonumber(meminfo:match("MemFree:%s+(%d+)")) or 0
        local mem_buffers = tonumber(meminfo:match("Buffers:%s+(%d+)")) or 0
        local mem_cached = tonumber(meminfo:match("Cached:%s+(%d+)")) or 0

        data.mem_total = math.floor(mem_total / 1024)
        data.mem_used = math.floor((mem_total - mem_free - mem_buffers - mem_cached) / 1024)
        data.mem_usage = mem_total > 0 and math.floor(((mem_total - mem_free - mem_buffers - mem_cached) / mem_total) * 100) or 0
    end

    local uptime_raw = sys.exec("cat /proc/uptime")
    if uptime_raw and uptime_raw ~= "" then
        local uptime_sec = tonumber(uptime_raw:match("^(%d+)")) or 0
        local days = math.floor(uptime_sec / 86400)
        local hours = math.floor((uptime_sec % 86400) / 3600)
        local mins = math.floor((uptime_sec % 3600) / 60)
        data.uptime = string.format("%dd %dh %dm", days, hours, mins)
        data.uptime_seconds = uptime_sec
    end

    local loadavg = sys.exec("cat /proc/loadavg")
    if loadavg and loadavg ~= "" then
        data.load_1min, data.load_5min, data.load_15min = loadavg:match("^(%S+)%s+(%S+)%s+(%S+)")
    end

    data.hostname = sys.hostname() or "CB-Shield-Q30"
    write_json(data)
end

function action_riskstatus()
    local data = parse_json_file("/tmp/cb-riskcontrol.json", { status = "no_data" })
    local proxy = get_proxy_state()

    data.service_running = service_running("cb-riskcontrol")
    data.check_interval = tonumber(trim(sys.exec("uci -q get cb-riskcontrol.main.check_interval"))) or 300
    data.risk_threshold = tonumber(trim(sys.exec("uci -q get cb-riskcontrol.main.risk_threshold"))) or 70
    data.action = trim(sys.exec("uci -q get cb-riskcontrol.main.action"))
    data.proxy_service = proxy.service
    data.proxy_running = proxy.running

    if data.action == "" then
        data.action = "warn"
    end

    write_json(data)
end

function action_runcheck()
    if not require_post() then
        return
    end

    sys.exec("/usr/bin/cb-riskcontrol check >/dev/null 2>&1 &")
    write_json({ status = "started" })
end

function action_network()
    local data = {
        interfaces = {
            get_iface_info("wan"),
            get_iface_info("lan")
        },
        wifi = {
            get_wifi_info("office_24g", "办公 WiFi 2.4G", "2.4GHz"),
            get_wifi_info("office_5g", "办公 WiFi 5G", "5GHz")
        },
        proxy = get_proxy_state()
    }

    local arp = trim(sys.exec("cat /proc/net/arp | grep -v 'IP address' | wc -l"))
    data.total_clients = tonumber(arp) or 0
    write_json(data)
end

function action_connections()
    local conntrack = trim(sys.exec("cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null"))
    local conntrack_max = trim(sys.exec("cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null"))
    local active = tonumber(conntrack) or 0
    local maxv = tonumber(conntrack_max) or 65536

    write_json({
        active_connections = active,
        max_connections = maxv,
        usage_percent = maxv > 0 and math.floor((active / maxv) * 100) or 0
    })
end

function action_health()
    local run = http.formvalue("run")
    if run == "1" then
        if not require_post() then
            return
        end
        sys.exec("/usr/bin/cb-healthcheck check >/dev/null 2>&1")
    end
    write_json(parse_json_file("/tmp/cb-health.json", { overall = "no_data" }))
end

function action_ha_status()
    local run = http.formvalue("run")
    if run == "1" then
        if not require_post() then
            return
        end
        sys.exec("/usr/bin/cb-ha-monitor check >/dev/null 2>&1")
    end
    write_json(parse_json_file("/tmp/cb-ha.json", { health = "no_data" }))
end

function action_dns_status()
    local run = http.formvalue("run")
    if run == "1" then
        if not require_post() then
            return
        end
        sys.exec("/usr/bin/cb-dns-guard check >/dev/null 2>&1")
    end
    write_json(parse_json_file("/tmp/cb-dns-health.json", { health = "no_data" }))
end

function action_events()
    local items = {}
    local raw = sys.exec("tail -n 200 /tmp/cb-events.log 2>/dev/null")

    for line in raw:gmatch("[^\r\n]+") do
        local obj = json.parse(line)
        if obj then
            table.insert(items, obj)
        end
    end

    write_json({ events = items, count = #items })
end

function action_wizard_status()
    local raw = sys.exec("/usr/bin/cb-wizard status 2>/dev/null")
    local data = json.parse(raw) or parse_json_file("/tmp/cb-wizard.json", { required = true, done = false })
    data.proxy_enabled = trim(sys.exec("uci -q get cb-wizard.main.proxy_enabled")) == "1"
    data.proxy_type = trim(sys.exec("uci -q get cb-wizard.main.proxy_type"))
    data.openclash_subscription = trim(sys.exec("uci -q get cb-wizard.main.openclash_subscription"))
    data.openclash_profile = trim(sys.exec("uci -q get cb-wizard.main.openclash_profile"))
    data.openclash_mode = trim(sys.exec("uci -q get cb-wizard.main.openclash_mode"))
    data.openclash_operation_mode = trim(sys.exec("uci -q get cb-wizard.main.openclash_operation_mode"))
    data.openclash_installed = service_exists("openclash")
    data.openclash_running = service_running("openclash")
    data.openclash_config_ready = trim(sys.exec("uci -q get openclash.config.config_path")) ~= ""

    if data.proxy_type == "" then
        data.proxy_type = "none"
    end
    if data.openclash_profile == "" then
        data.openclash_profile = "cbshield"
    end
    if data.openclash_mode == "" then
        data.openclash_mode = "rule"
    end
    if data.openclash_operation_mode == "" then
        data.openclash_operation_mode = "fake-ip"
    end

    write_json(data)
end

function action_wizard_apply()
    if not require_post() then
        return
    end

    local password = http.formvalue("password") or ""
    local timezone = http.formvalue("timezone") or "CST-8"
    local zonename = http.formvalue("zonename") or "Asia/Shanghai"
    local wan_proto = http.formvalue("wan_proto") or "dhcp"
    local wan_user = http.formvalue("wan_user") or ""
    local wan_pass = http.formvalue("wan_pass") or ""
    local office_ssid = http.formvalue("office_ssid") or "CB-Shield-Office"
    local office_key = http.formvalue("office_key") or "CBShield@Office2024"
    local office5_ssid = http.formvalue("office5_ssid") or "CB-Shield-Office-5G"
    local proxy_enabled = http.formvalue("proxy_enabled") or "0"
    local proxy_type = http.formvalue("proxy_type") or "none"
    local openclash_subscription = http.formvalue("openclash_subscription") or ""
    local openclash_profile = http.formvalue("openclash_profile") or "cbshield"
    local openclash_mode = http.formvalue("openclash_mode") or "rule"
    local openclash_operation_mode = http.formvalue("openclash_operation_mode") or "fake-ip"

    local cmd = string.format(
        "/usr/bin/cb-wizard apply %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s 2>/dev/null",
        shq(password), shq(timezone), shq(zonename), shq(wan_proto), shq(wan_user), shq(wan_pass),
        shq(office_ssid), shq(office_key), shq(office5_ssid), shq(proxy_enabled), shq(proxy_type),
        shq(openclash_subscription), shq(openclash_profile), shq(openclash_mode), shq(openclash_operation_mode)
    )
    local out = sys.exec(cmd)
    write_json(json.parse(out) or { status = "error", message = "wizard_apply_failed" })
end

function action_upgrade_check()
    if not require_post() then
        return
    end

    local image = http.formvalue("image") or ""
    local sha = http.formvalue("sha256") or ""

    if image == "" then
        http.status(400, "Bad Request")
        write_json({ status = "error", message = "image_required" })
        return
    end

    local cmd = "/usr/bin/cb-safe-upgrade check " .. shq(image)
    if sha ~= "" then
        cmd = cmd .. " " .. shq(sha)
    end

    local out = sys.exec(cmd .. " 2>/dev/null")
    write_json(json.parse(out) or parse_json_file("/tmp/cb-upgrade-check.json", { all_ok = false, note = "check_failed" }))
end
