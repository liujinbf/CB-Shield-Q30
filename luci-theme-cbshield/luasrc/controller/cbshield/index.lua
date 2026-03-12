module("luci.controller.cbshield.index", package.seeall)

function index()
    -- CB-Shield 主导航入口
    local root = entry({"admin", "cbshield"}, firstchild(), "CB-Shield", 10)
    root.dependent = false
    root.icon = "cbshield"

    -- 仪表盘页面
    entry({"admin", "cbshield", "dashboard"}, template("cbshield/dashboard"), _("仪表盘"), 10)

    -- 风控状态页面
    entry({"admin", "cbshield", "riskcontrol"}, template("cbshield/riskcontrol"), _("IP 风控"), 20)

    -- 网络状态页面
    entry({"admin", "cbshield", "network_status"}, template("cbshield/network_status"), _("网络状态"), 30)
end
