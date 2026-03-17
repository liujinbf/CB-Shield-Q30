module("luci.controller.cbshield.api", package.seeall)

local json = require("luci.jsonc")
local sys = require("luci.sys")
local http = require("luci.http")

function index()
    entry({"admin", "cbshield", "api", "sysinfo"}, call("action_sysinfo")).leaf = true
    entry({"admin", "cbshield", "api", "riskstatus"}, call("action_riskstatus")).leaf = true
    entry({"admin", "cbshield", "api", "runcheck"}, call("action_runcheck")).leaf = true
    entry({"admin", "cbshield", "api", "network"}, call("action_network")).leaf = true
    entry({"admin", "cbshield", "api", "toggle_shop"}, call("action_toggle_shop")).leaf = true
    entry({"admin", "cbshield", "api", "connections"}, call("action_connections")).leaf = true

    entry({"admin", "cbshield", "api", "health"}, call("action_health")).leaf = true
    entry({"admin", "cbshield", "api", "ha_status"}, call("action_ha_status")).leaf = true
    entry({"admin", "cbshield", "api", "dns_status"}, call("action_dns_status")).leaf = true
    entry({"admin", "cbshield", "api", "events"}, call("action_events")).leaf = true

    entry({"admin", "cbshield", "api", "wizard_status"}, call("action_wizard_status")).leaf = true
    entry({"admin", "cbshield", "api", "wizard_apply"}, call("action_wizard_apply")).leaf = true

    entry({"admin", "cbshield", "api", "policy_status"}, call("action_policy_status")).leaf = true
    entry({"admin", "cbshield", "api", "apply_template"}, call("action_apply_template")).leaf = true

    entry({"admin", "cbshield", "api", "upgrade_check"}, call("action_upgrade_check")).leaf = true
end

local function trim(s)
    if not s then
        return ""
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shq(v)
    v = tostring(v or "")
    return "'" .. v:gsub("'", "'\\''") .. "'"
end

local function write_json(data)
    http.prepare_content("application/json")
    http.write(json.stringify(data))
end

local function parse_json_file(path, default_data)
    local f = io.open(path, "r")
    if not f then
        return default_data
    end
    local content = f:read("*a")
    f:close()
    return json.parse(content) or default_data
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
        local s = json.parse(status) or {}
        info.up = s.up or false
        info.disabled = s.disabled or false

        if s["ipv4-address"] and s["ipv4-address"][1] then
            info.ip = s["ipv4-address"][1].address or ""
        else
            info.ip = trim(sys.exec("uci -q get network." .. iface .. ".ipaddr"))
        end

        if s.device then
            local dev = s.device
            local rx = tonumber(trim(sys.exec("cat /sys/class/net/" .. dev .. "/statistics/rx_bytes 2>/dev/null"))) or 0
            local tx = tonumber(trim(sys.exec("cat /sys/class/net/" .. dev .. "/statistics/tx_bytes 2>/dev/null"))) or 0
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
    local pid = trim(sys.exec("pgrep -f 'cb-riskcontrol daemon'"))
    data.service_running = pid ~= ""
    data.check_interval = tonumber(trim(sys.exec("uci -q get cb-riskcontrol.main.check_interval"))) or 300
    data.risk_threshold = tonumber(trim(sys.exec("uci -q get cb-riskcontrol.main.risk_threshold"))) or 70
    data.action = trim(sys.exec("uci -q get cb-riskcontrol.main.action"))
    if data.action == "" then
        data.action = "warn"
    end
    write_json(data)
end

function action_runcheck()
    sys.exec("/usr/bin/cb-riskcontrol check >/dev/null 2>&1 &")
    write_json({ status = "started" })
end

function action_network()
    local data = { interfaces = {}, shops = {} }

    for _, iface in ipairs({ "lan", "wan" }) do
        table.insert(data.interfaces, get_iface_info(iface))
    end

    for i = 1, 5 do
        local id = "shop" .. i
        local info = get_iface_info(id)
        local wifi_id = id .. "_5g"
        info.ssid = trim(sys.exec("uci -q get wireless." .. wifi_id .. ".ssid"))
        if info.ssid == "" then
            info.ssid = "N/A"
        end
        local disabled = trim(sys.exec("uci -q get wireless." .. wifi_id .. ".disabled"))
        info.wifi_enabled = (disabled == "" or disabled == "0")
        info.template = trim(sys.exec("uci -q get cb-policy." .. id .. ".template"))
        if info.template == "" then
            info.template = "direct"
        end
        table.insert(data.shops, info)
    end

    local arp = trim(sys.exec("cat /proc/net/arp | grep -v 'IP address' | wc -l"))
    data.total_clients = tonumber(arp) or 0
    write_json(data)
end

function action_toggle_shop()
    local id = http.formvalue("id")
    local enable = http.formvalue("enable") == "1"

    if not id or not id:match("^shop[1-5]$") then
        http.status(400, "Bad Request")
        write_json({ status = "bad_request" })
        return
    end

    local disabled_val = enable and "0" or "1"
    local wifi_id = id .. "_5g"

    sys.exec("uci set network." .. id .. ".disabled=" .. shq(disabled_val))
    sys.exec("uci set dhcp." .. id .. ".ignore=" .. shq(disabled_val))
    sys.exec("uci set wireless." .. wifi_id .. ".disabled=" .. shq(disabled_val))
    sys.exec("uci commit network; uci commit dhcp; uci commit wireless")
    sys.exec("/sbin/reload_config >/dev/null 2>&1 &")
    sys.exec("wifi reload >/dev/null 2>&1 &")
    sys.exec("/usr/bin/cb-eventlog write network " .. shq("toggle " .. id .. " enable=" .. tostring(enable)))

    write_json({ status = "success", enabled = enable })
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
        sys.exec("/usr/bin/cb-healthcheck check >/dev/null 2>&1")
    end
    write_json(parse_json_file("/tmp/cb-health.json", { overall = "no_data" }))
end

function action_ha_status()
    local run = http.formvalue("run")
    if run == "1" then
        sys.exec("/usr/bin/cb-ha-monitor check >/dev/null 2>&1")
    end
    write_json(parse_json_file("/tmp/cb-ha.json", { health = "no_data" }))
end

function action_dns_status()
    local run = http.formvalue("run")
    if run == "1" then
        sys.exec("/usr/bin/cb-dns-guard check >/dev/null 2>&1")
    end
    write_json(parse_json_file("/tmp/cb-dns-health.json", { health = "no_data" }))
end

function action_events()
    local lines = {}
    local raw = sys.exec("tail -n 200 /tmp/cb-events.log 2>/dev/null")
    for line in raw:gmatch("[^\r\n]+") do
        local obj = json.parse(line)
        if obj then
            table.insert(lines, obj)
        end
    end
    write_json({ events = lines, count = #lines })
end

function action_wizard_status()
    local raw = sys.exec("/usr/bin/cb-wizard status 2>/dev/null")
    local data = json.parse(raw) or parse_json_file("/tmp/cb-wizard.json", { required = true, done = false })
    write_json(data)
end

function action_wizard_apply()
    local password = http.formvalue("password") or ""
    local timezone = http.formvalue("timezone") or "CST-8"
    local zonename = http.formvalue("zonename") or "Asia/Shanghai"
    local wan_proto = http.formvalue("wan_proto") or "dhcp"
    local wan_user = http.formvalue("wan_user") or ""
    local wan_pass = http.formvalue("wan_pass") or ""
    local office_ssid = http.formvalue("office_ssid") or "CB-Shield-Office"
    local office_key = http.formvalue("office_key") or "CBShield@Office2024"
    local office5_ssid = http.formvalue("office5_ssid") or "CB-Shield-Office-5G"

    local cmd = string.format(
        "/usr/bin/cb-wizard apply %s %s %s %s %s %s %s %s %s 2>/dev/null",
        shq(password), shq(timezone), shq(zonename), shq(wan_proto), shq(wan_user), shq(wan_pass),
        shq(office_ssid), shq(office_key), shq(office5_ssid)
    )
    local out = sys.exec(cmd)
    write_json(json.parse(out) or { status = "error", message = "wizard_apply_failed" })
end

function action_policy_status()
    local run = http.formvalue("run")
    if run == "1" then
        sys.exec("/usr/bin/cb-policy-engine run_once >/dev/null 2>&1")
    end
    write_json(parse_json_file("/tmp/cb-policy.json", { enabled = false, shops = {} }))
end

function action_apply_template()
    local id = http.formvalue("id")
    local template = http.formvalue("template")
    if not id or not id:match("^shop[1-5]$") then
        http.status(400, "Bad Request")
        write_json({ status = "bad_shop" })
        return
    end
    if template ~= "direct" and template ~= "proxy" and template ~= "blocked" then
        http.status(400, "Bad Request")
        write_json({ status = "bad_template" })
        return
    end

    local out = trim(sys.exec("/usr/bin/cb-policy-engine apply_template " .. shq(id) .. " " .. shq(template) .. " 2>/dev/null"))
    if out == "ok" then
        write_json({ status = "success", id = id, template = template })
    else
        write_json({ status = "error", message = out })
    end
end

function action_upgrade_check()
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
