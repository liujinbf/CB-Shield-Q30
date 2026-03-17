/**
 * CB-Shield Dashboard data polling and rendering
 */
(function() {
    'use strict';

    var API_BASE = '/admin/cbshield/api';
    var POLL_INTERVAL = 5000;

    function initDashboard() {
        if (!document.querySelector('.cb-dashboard')) return;
        if (!document.getElementById('cpu-value')) return;

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
        ajaxGet(API_BASE + '/sysinfo', function(data) {
            if (!data) return;

            setElementText('cpu-value', data.cpu_usage);
            colorizeValue('card-cpu', data.cpu_usage, [60, 85]);

            setElementText('mem-value', data.mem_usage);
            setElementText('mem-detail', (data.mem_used || 0) + ' / ' + (data.mem_total || 0) + ' MB');
            colorizeValue('card-memory', data.mem_usage, [70, 90]);

            setElementText('uptime-value', data.uptime);

            setElementText('load-1', data.load_1min);
            setElementText('load-5', data.load_5min);
            setElementText('load-15', data.load_15min);
        });
    }

    function fetchRiskStatus() {
        ajaxGet(API_BASE + '/riskstatus', function(data) {
            if (!data) return;

            var indicator = document.getElementById('risk-indicator');
            if (data.risk_score !== undefined) {
                setElementText('risk-score', data.risk_score);
                var levelMap = {
                    low: '安全',
                    medium: '注意',
                    high: '高风险',
                    critical: '危险'
                };
                setElementText('risk-label', levelMap[data.risk_level] || '未知');
                if (indicator) {
                    indicator.style.background = getRiskGradient(data.risk_level);
                }
            }

            setElementText('risk-ip', data.ip);
            setElementText('risk-location', (data.country || '') + ' ' + (data.city || ''));
            setElementText('risk-isp', data.isp);
            setElementText('risk-proxy', data.is_proxy ? '已检测到代理' : '非代理');
            setElementText('risk-time', data.timestamp);
            setElementText('risk-action', data.action_taken || '无');

            if (!data.service_running && data.status === 'service_not_running') {
                setElementText('risk-label', '服务未启动');
            }
        });
    }

    function fetchNetworkStatus() {
        ajaxGet(API_BASE + '/network', function(data) {
            if (!data) return;

            var allIfaces = [];
            if (Array.isArray(data.interfaces)) {
                allIfaces = allIfaces.concat(data.interfaces);
            }
            if (Array.isArray(data.shops)) {
                allIfaces = allIfaces.concat(data.shops);
            }

            var ifaceMap = {
                wan: {ip: 'wan-ip', rx: 'wan-rx', tx: 'wan-tx'},
                lan: {ip: 'office-ip', rx: 'office-rx', tx: 'office-tx'},
                shop1: {ip: 'guest-ip', rx: 'guest-rx', tx: 'guest-tx'},
                shop2: {ip: 'ecom-ip', rx: 'ecom-rx', tx: 'ecom-tx'}
            };

            for (var i = 0; i < allIfaces.length; i++) {
                var iface = allIfaces[i];
                var els = ifaceMap[iface.name];
                if (!els) continue;

                setElementText(els.ip, iface.ip || '--');
                setElementText(els.rx, iface.rx_human || '--');
                setElementText(els.tx, iface.tx_human || '--');
            }
        });
    }

    function fetchConnections() {
        ajaxGet(API_BASE + '/connections', function(data) {
            if (!data) return;
            setElementText('conn-value', data.active_connections);
            setElementText('conn-detail', '最大 ' + data.max_connections);
        });
    }

    function ajaxGet(url, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    callback(JSON.parse(xhr.responseText));
                } catch (e) {
                    console.error('JSON parse failed:', e);
                }
            }
        };
        xhr.onerror = function() {
            console.error('Request failed:', url);
        };
        xhr.send();
    }

    function setElementText(id, text) {
        var el = document.getElementById(id);
        if (el) {
            el.textContent = (text !== undefined && text !== null) ? text : '--';
        }
    }

    function colorizeValue(cardId, value, thresholds) {
        var card = document.getElementById(cardId);
        if (!card) return;

        card.style.borderLeftWidth = '3px';
        card.style.borderLeftStyle = 'solid';

        if (value >= thresholds[1]) {
            card.style.borderLeftColor = '#E74C3C';
        } else if (value >= thresholds[0]) {
            card.style.borderLeftColor = '#F39C12';
        } else {
            card.style.borderLeftColor = '#27AE60';
        }
    }

    function getRiskGradient(level) {
        var gradients = {
            low: 'linear-gradient(135deg, #27AE60, #00D4AA)',
            medium: 'linear-gradient(135deg, #F39C12, #E67E22)',
            high: 'linear-gradient(135deg, #E74C3C, #C0392B)',
            critical: 'linear-gradient(135deg, #C0392B, #8E2424)'
        };
        return gradients[level] || gradients.low;
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initDashboard);
    } else {
        initDashboard();
    }
})();
