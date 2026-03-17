module("luci.controller.cbshield.index", package.seeall)

local fs = require("nixio.fs")

function index()
    local root = entry({"admin", "cbshield"}, firstchild(), _("CB-Shield"), 10)
    root.dependent = false
    root.icon = "cbshield"

    entry({"admin", "cbshield", "dashboard"}, template("cbshield/dashboard"), _("仪表盘"), 10)
    entry({"admin", "cbshield", "riskcontrol"}, template("cbshield/riskcontrol"), _("IP 风控"), 20)
    entry({"admin", "cbshield", "network_status"}, template("cbshield/network_status"), _("网络状态"), 30)

    -- 只有检测到 Passwall 控制器时才展示“海外线路”快捷入口
    if fs.access("/usr/lib/lua/luci/controller/passwall.lua") then
        entry({"admin", "cbshield", "overseas_line"}, alias("admin", "services", "passwall"), _("海外线路"), 40)
    end
end
