module("luci.controller.cbshield.index", package.seeall)

local fs = require("nixio.fs")

function index()
    local root = entry({"admin", "cbshield"}, firstchild(), _("CB-Shield"), 10)
    root.dependent = false
    root.icon = "cbshield"

    entry({"admin", "cbshield", "dashboard"}, template("cbshield/dashboard"), _("仪表盘"), 10)
    entry({"admin", "cbshield", "riskcontrol"}, template("cbshield/riskcontrol"), _("IP 风控"), 20)
    entry({"admin", "cbshield", "network_status"}, template("cbshield/network_status"), _("多 WiFi"), 30)
    entry({"admin", "cbshield", "ops_center"}, template("cbshield/ops_center"), _("运维中心"), 40)
    entry({"admin", "cbshield", "wizard"}, template("cbshield/wizard"), _("首次向导"), 50)
    entry({"admin", "cbshield", "timeline"}, template("cbshield/timeline"), _("事件时间线"), 60)

    if fs.access("/usr/lib/lua/luci/controller/passwall.lua") then
        entry({"admin", "cbshield", "overseas_line"}, alias("admin", "services", "passwall"), _("海外线路"), 70)
    end
end
