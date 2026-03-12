/**
 * CB-Shield Dashboard JS
 * 仪表盘数据轮询与渲染
 */
(function() {
    'use strict';

    var API_BASE = '/admin/cbshield/api';
    var POLL_INTERVAL = 5000; // 5 秒轮询

    /**
     * 初始化仪表盘
     */
    function initDashboard() {
        // 仅在仪表盘页面执行
        if (!document.querySelector('.cb-dashboard')) return;
        if (!document.getElementById('cpu-value')) return;

        // 立即加载一次
        fetchSysinfo();
        fetchRiskStatus();
        fetchNetworkStatus();
        fetchConnections();

        // 定时轮询
        setInterval(fetchSysinfo, POLL_INTERVAL);
        setInterval(fetchRiskStatus, 30000);     // 30秒
        setInterval(fetchNetworkStatus, 10000);   // 10秒
        setInterval(fetchConnections, POLL_INTERVAL);
    }

    /**
     * 获取系统信息
     */
    function fetchSysinfo() {
        ajaxGet(API_BASE + '/sysinfo', function(data) {
            if (!data) return;

            // CPU
            setElementText('cpu-value', data.cpu_usage);
            colorizeValue('card-cpu', data.cpu_usage, [60, 85]);

            // 内存
            setElementText('mem-value', data.mem_usage);
            setElementText('mem-detail', data.mem_used + ' / ' + data.mem_total + ' MB');
            colorizeValue('card-memory', data.mem_usage, [70, 90]);

            // 运行时间
            setElementText('uptime-value', data.uptime);

            // 负载
            setElementText('load-1', data.load_1min);
            setElementText('load-5', data.load_5min);
            setElementText('load-15', data.load_15min);
        });
    }

    /**
     * 获取风控状态
     */
    function fetchRiskStatus() {
        ajaxGet(API_BASE + '/riskstatus', function(data) {
            if (!data) return;

            var scoreEl = document.getElementById('risk-score');
            var labelEl = document.getElementById('risk-label');
            var indicator = document.getElementById('risk-indicator');

            if (data.risk_score !== undefined) {
                setElementText('risk-score', data.risk_score);

                // 风险等级标签
                var levelMap = {
                    'low': '✅ 安全',
                    'medium': '⚠️ 注意',
                    'high': '🟠 高风险',
                    'critical': '🔴 危险'
                };
                setElementText('risk-label', levelMap[data.risk_level] || '未知');

                // 风险指示器颜色
                if (indicator) {
                    indicator.style.background = getRiskGradient(data.risk_level);
                }
            }

            setElementText('risk-ip', data.ip);
            setElementText('risk-location', (data.country || '') + ' ' + (data.city || ''));
            setElementText('risk-isp', data.isp);
            setElementText('risk-proxy', data.is_proxy ? '⚠️ 已检测到代理' : '✅ 非代理');
            setElementText('risk-time', data.timestamp);
            setElementText('risk-action', data.action_taken || '无');

            // 服务状态
            if (!data.service_running && data.status === 'service_not_running') {
                setElementText('risk-label', '服务未启动');
            }
        });
    }

    /**
     * 获取网络状态
     */
    function fetchNetworkStatus() {
        ajaxGet(API_BASE + '/network', function(data) {
            if (!data || !data.interfaces) return;

            var ifaceMap = {
                'wan': {ip: 'wan-ip', rx: 'wan-rx', tx: 'wan-tx'},
                'vlan_office': {ip: 'office-ip', rx: 'office-rx', tx: 'office-tx'},
                'vlan_guest': {ip: 'guest-ip', rx: 'guest-rx', tx: 'guest-tx'},
                'vlan_ecom': {ip: 'ecom-ip', rx: 'ecom-rx', tx: 'ecom-tx'}
            };

            for (var i = 0; i < data.interfaces.length; i++) {
                var iface = data.interfaces[i];
                var els = ifaceMap[iface.name];
                if (els) {
                    setElementText(els.ip, iface.ip || '--');
                    setElementText(els.rx, iface.rx_human || '--');
                    setElementText(els.tx, iface.tx_human || '--');
                }
            }
        });
    }

    /**
     * 获取连接数
     */
    function fetchConnections() {
        ajaxGet(API_BASE + '/connections', function(data) {
            if (!data) return;
            setElementText('conn-value', data.active_connections);
            setElementText('conn-detail', '最大: ' + data.max_connections);
        });
    }

    // --- 辅助函数 ---

    function ajaxGet(url, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    callback(JSON.parse(xhr.responseText));
                } catch(e) {
                    console.error('JSON 解析失败:', e);
                }
            }
        };
        xhr.onerror = function() {
            console.error('请求失败:', url);
        };
        xhr.send();
    }

    function setElementText(id, text) {
        var el = document.getElementById(id);
        if (el) el.textContent = (text !== undefined && text !== null) ? text : '--';
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
            'low': 'linear-gradient(135deg, #27AE60, #00D4AA)',
            'medium': 'linear-gradient(135deg, #F39C12, #E67E22)',
            'high': 'linear-gradient(135deg, #E74C3C, #C0392B)',
            'critical': 'linear-gradient(135deg, #C0392B, #8E2424)'
        };
        return gradients[level] || gradients['low'];
    }

    // DOM Ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initDashboard);
    } else {
        initDashboard();
    }
})();
