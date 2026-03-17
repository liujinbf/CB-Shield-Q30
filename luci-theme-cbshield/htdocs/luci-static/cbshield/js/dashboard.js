/**
 * CB-Shield 仪表盘轮询逻辑
 */
(function() {
    "use strict";

    var API_BASE = "/cgi-bin/luci/admin/cbshield/api";
    var POLL_INTERVAL = 5000;

    function initDashboard() {
        if (!document.querySelector(".cb-dashboard")) return;
        if (!document.getElementById("cpu-value")) return;

        fetchSysinfo();
        fetchRiskStatus();
        fetchNetworkStatus();
        fetchConnections();

        setInterval(fetchSysinfo, POLL_INTERVAL);
        setInterval(fetchRiskStatus, 30000);
        setInterval(fetchNetworkStatus, 10000);
        setInterval(fetchConnections, POLL_INTERVAL);
    }

    function fetchSysinfo() {
        ajaxGet(API_BASE + "/sysinfo", function(data) {
            if (!data) return;

            setElementText("cpu-value", data.cpu_usage);
            colorizeValue("card-cpu", data.cpu_usage, [60, 85]);

            setElementText("mem-value", data.mem_usage);
            setElementText("mem-detail", (data.mem_used || 0) + " / " + (data.mem_total || 0) + " MB");
            colorizeValue("card-memory", data.mem_usage, [70, 90]);

            setElementText("uptime-value", data.uptime);
            setElementText("load-1", data.load_1min);
            setElementText("load-5", data.load_5min);
            setElementText("load-15", data.load_15min);
        });
    }

    function fetchRiskStatus() {
        ajaxGet(API_BASE + "/riskstatus", function(data) {
            if (!data) return;

            var indicator = document.getElementById("risk-indicator");
            var levelMap = {
                low: "低风险",
                medium: "中风险",
                high: "高风险",
                critical: "严重风险"
            };

            if (data.risk_score !== undefined) {
                setElementText("risk-score", data.risk_score);
                setElementText("risk-label", levelMap[data.risk_level] || "未知");
                if (indicator) {
                    indicator.style.background = getRiskGradient(data.risk_level);
                }
            } else {
                setElementText("risk-score", "--");
                setElementText("risk-label", data.status || "无数据");
            }

            setElementText("risk-service", buildProxyStatus(data));
            setElementText("risk-ip", data.ip || "--");
            setElementText("risk-location", joinText([data.country, data.city]));
            setElementText("risk-isp", data.isp || "--");
            setElementText("risk-proxy", data.is_proxy ? "检测到代理特征" : "未检测到代理特征");
            setElementText("risk-time", data.timestamp || "--");
            setElementText("risk-action", data.action_taken || data.action || "--");

            if (!data.service_running) {
                setElementText("risk-label", "风控服务未运行");
            }
        });
    }

    function fetchNetworkStatus() {
        ajaxGet(API_BASE + "/network", function(data) {
            if (!data) return;

            var ifaceMap = {};
            (data.interfaces || []).forEach(function(iface) {
                ifaceMap[iface.name] = iface;
            });

            var wifiMap = {};
            (data.wifi || []).forEach(function(item) {
                wifiMap[item.id] = item;
            });

            updateInterfaceCard("wan", ifaceMap.wan);
            updateInterfaceCard("lan", ifaceMap.lan);
            updateWifiCard("wifi24", wifiMap.office_24g);
            updateWifiCard("wifi5", wifiMap.office_5g);

            setElementText("clients-value", data.total_clients || 0);
            setElementText("proxy-value", readableServiceName(data.proxy && data.proxy.service));
            setElementText("proxy-detail", data.proxy && data.proxy.running ? "运行中" : "未运行");
        });
    }

    function fetchConnections() {
        ajaxGet(API_BASE + "/connections", function(data) {
            if (!data) return;

            setElementText("conn-value", data.active_connections);
            setElementText("conn-detail", "最大 " + data.max_connections);
            colorizeValue("card-connections", data.usage_percent || 0, [50, 75]);
        });
    }

    function updateInterfaceCard(prefix, iface) {
        if (!iface) return;

        setElementText(prefix + "-status", iface.up ? "在线" : "离线");
        setElementText(prefix + "-ip", iface.ip || "--");
        setElementText(prefix + "-rx", iface.rx_human || "--");
        setElementText(prefix + "-tx", iface.tx_human || "--");
    }

    function updateWifiCard(prefix, wifi) {
        if (!wifi) return;

        setElementText(prefix + "-ssid", wifi.ssid || "--");
        setElementText(prefix + "-status", wifi.enabled ? "启用" : "禁用");
        setElementText(prefix + "-network", wifi.network || "--");
    }

    function buildProxyStatus(data) {
        var service = readableServiceName(data.proxy_service);
        var status = data.proxy_running ? "运行中" : "未运行";
        if (service === "--") return status;
        return service + " / " + status;
    }

    function readableServiceName(name) {
        if (!name || name === "none") return "--";
        if (name === "openclash") return "OpenClash";
        if (name === "passwall") return "Passwall";
        return name;
    }

    function joinText(parts) {
        return parts.filter(Boolean).join(" ") || "--";
    }

    function ajaxGet(url, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    callback(JSON.parse(xhr.responseText));
                } catch (error) {
                    console.error("JSON parse failed:", error);
                }
            }
        };
        xhr.onerror = function() {
            console.error("Request failed:", url);
        };
        xhr.send();
    }

    function setElementText(id, text) {
        var element = document.getElementById(id);
        if (element) {
            element.textContent = text !== undefined && text !== null ? text : "--";
        }
    }

    function colorizeValue(cardId, value, thresholds) {
        var card = document.getElementById(cardId);
        if (!card) return;

        card.style.borderLeftWidth = "3px";
        card.style.borderLeftStyle = "solid";

        if (value >= thresholds[1]) {
            card.style.borderLeftColor = "#E74C3C";
        } else if (value >= thresholds[0]) {
            card.style.borderLeftColor = "#F39C12";
        } else {
            card.style.borderLeftColor = "#27AE60";
        }
    }

    function getRiskGradient(level) {
        var gradients = {
            low: "linear-gradient(135deg, #27AE60, #00D4AA)",
            medium: "linear-gradient(135deg, #F39C12, #E67E22)",
            high: "linear-gradient(135deg, #E74C3C, #C0392B)",
            critical: "linear-gradient(135deg, #C0392B, #8E2424)"
        };
        return gradients[level] || gradients.low;
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initDashboard);
    } else {
        initDashboard();
    }
})();
