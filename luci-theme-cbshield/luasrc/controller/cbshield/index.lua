module("luci.controller.cbshield.index", package.seeall)

local fs = require("nixio.fs")
local sys = require("luci.sys")

local function wizard_required()
    if fs.access("/etc/cbshield/wizard_required") then
        return true
    end

    local required = (sys.exec("uci -q get cb-wizard.main.required 2>/dev/null") or ""):gsub("%s+$", "")
    return required == "1"
end

local function has_controller(name)
    return fs.access("/usr/lib/lua/luci/controller/" .. name .. ".lua")
end

local function get_proxy_target(require_wizard)
    if require_wizard then
        return alias("admin", "cbshield", "wizard")
    end

    if has_controller("openclash") then
        return alias("admin", "services", "openclash")
    end

    if has_controller("passwall") then
        return alias("admin", "services", "passwall")
    end

    return nil
end

function index()
    local require_wizard = wizard_required()
    local root_target = firstchild()

    if require_wizard then
        root_target = alias("admin", "cbshield", "wizard")
    end

    local root = entry({"admin", "cbshield"}, root_target, _("CB-Shield"), 10)
    root.dependent = false
    root.icon = "cbshield"

    local dashboard_target = template("cbshield/dashboard")
    local risk_target = template("cbshield/riskcontrol")
    local network_target = template("cbshield/network_status")
    local ops_target = template("cbshield/ops_center")
    local timeline_target = template("cbshield/timeline")

    if require_wizard then
        dashboard_target = alias("admin", "cbshield", "wizard")
        risk_target = alias("admin", "cbshield", "wizard")
        network_target = alias("admin", "cbshield", "wizard")
        ops_target = alias("admin", "cbshield", "wizard")
        timeline_target = alias("admin", "cbshield", "wizard")
    end

    entry({"admin", "cbshield", "dashboard"}, dashboard_target, _("仪表盘"), 10)
    entry({"admin", "cbshield", "riskcontrol"}, risk_target, _("IP 风控"), 20)
    entry({"admin", "cbshield", "network_status"}, network_target, _("网络状态"), 30)
    entry({"admin", "cbshield", "ops_center"}, ops_target, _("运维中心"), 40)
    entry({"admin", "cbshield", "wizard"}, template("cbshield/wizard"), _("首次向导"), 50)
    entry({"admin", "cbshield", "timeline"}, timeline_target, _("事件时间线"), 60)

    local proxy_target = get_proxy_target(require_wizard)
    if proxy_target then
        entry({"admin", "cbshield", "overseas_line"}, proxy_target, _("代理配置"), 70)
    end
end
