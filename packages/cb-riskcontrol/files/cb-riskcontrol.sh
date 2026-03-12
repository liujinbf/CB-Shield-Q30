#!/bin/sh
# ============================================================
# CB-Shield-Q30 IP 风控脚本
# 功能：检测 WAN IP 是否为代理/VPN/托管 IP
#       风险评分 + 自动告警/断网/切换
# ============================================================

CONF_FILE="/etc/config/cb-riskcontrol"
STATUS_FILE="/tmp/cb-riskcontrol.json"
LOG_TAG="cb-riskcontrol"
LOCK_FILE="/tmp/cb-riskcontrol.lock"
CHECK_INTERVAL=300   # 默认 5 分钟

# --- 加载配置 ---
load_config() {
    ENABLED=$(uci -q get cb-riskcontrol.main.enabled || echo "1")
    CHECK_INTERVAL=$(uci -q get cb-riskcontrol.main.check_interval || echo "300")
    ACTION=$(uci -q get cb-riskcontrol.main.action || echo "warn")
    RISK_THRESHOLD=$(uci -q get cb-riskcontrol.main.risk_threshold || echo "70")
    API_PROVIDER=$(uci -q get cb-riskcontrol.main.api_provider || echo "ip-api")
}

# --- 日志 ---
log_info() {
    logger -t "$LOG_TAG" -p daemon.info "$1"
}

log_warn() {
    logger -t "$LOG_TAG" -p daemon.warn "WARNING: $1"
}

log_err() {
    logger -t "$LOG_TAG" -p daemon.err "ERROR: $1"
}

# --- 获取 WAN IP ---
get_wan_ip() {
    local ip=""
    # 优先从接口获取
    ip=$(ifconfig eth0.2 2>/dev/null | grep 'inet addr' | awk -F: '{print $2}' | awk '{print $1}')
    # 备用: 从外部获取
    if [ -z "$ip" ] || echo "$ip" | grep -qE "^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)"; then
        ip=$(curl -s --connect-timeout 5 --max-time 10 "https://api.ipify.org" 2>/dev/null)
    fi
    echo "$ip"
}

# --- IP 风险检测 (ip-api.com) ---
check_ip_risk_ipapi() {
    local ip="$1"
    local result=""

    result=$(curl -s --connect-timeout 10 --max-time 15 \
        "http://ip-api.com/json/${ip}?fields=status,message,country,countryCode,region,city,isp,org,as,proxy,hosting,timezone,query" \
        2>/dev/null)

    if [ -z "$result" ]; then
        echo '{"error":"API request failed","risk_score":0}'
        return 1
    fi

    # 解析字段
    local is_proxy=$(echo "$result" | jsonfilter -e '@.proxy' 2>/dev/null)
    local is_hosting=$(echo "$result" | jsonfilter -e '@.hosting' 2>/dev/null)
    local country=$(echo "$result" | jsonfilter -e '@.country' 2>/dev/null)
    local isp=$(echo "$result" | jsonfilter -e '@.isp' 2>/dev/null)
    local org=$(echo "$result" | jsonfilter -e '@.org' 2>/dev/null)
    local asn=$(echo "$result" | jsonfilter -e '@.as' 2>/dev/null)
    local city=$(echo "$result" | jsonfilter -e '@.city' 2>/dev/null)
    local timezone=$(echo "$result" | jsonfilter -e '@.timezone' 2>/dev/null)

    # ========== 自动时区对齐 (V2.2 Gold 特性) ==========
    if [ -n "$timezone" ] && [ "$timezone" != "null" ]; then
        local current_zone=$(uci -q get system.@system[0].zonename)
        if [ "$timezone" != "$current_zone" ]; then
            log_info "时区变化：$current_zone -> $timezone，正在自动同步对齐"
            uci set system.@system[0].zonename="$timezone"
            uci commit system
            /etc/init.d/system reload
        fi
    fi
    # =================================================

    # --- 风险评分算法 ---
    local risk_score=0
    local risk_factors=""

    # 代理 IP: +50分
    if [ "$is_proxy" = "true" ]; then
        risk_score=$((risk_score + 50))
        risk_factors="${risk_factors}proxy_detected,"
    fi

    # 托管/数据中心 IP: +30分
    if [ "$is_hosting" = "true" ]; then
        risk_score=$((risk_score + 30))
        risk_factors="${risk_factors}hosting_ip,"
    fi

    # 检查已知 VPN/代理 ASN 关键词
    echo "$org $isp" | grep -qiE "vpn|proxy|tunnel|tor|hosting|cloud|server|data.?center|cdn" && {
        risk_score=$((risk_score + 20))
        risk_factors="${risk_factors}suspicious_org,"
    }

    # 输出 JSON 格式结果
    cat << EOF
{
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "ip": "${ip}",
    "country": "${country}",
    "city": "${city}",
    "isp": "${isp}",
    "org": "${org}",
    "asn": "${asn}",
    "is_proxy": ${is_proxy:-false},
    "is_hosting": ${is_hosting:-false},
    "risk_score": ${risk_score},
    "risk_level": "$(get_risk_level $risk_score)",
    "risk_factors": "${risk_factors%,}",
    "action_taken": "none"
}
EOF
}

# --- 风险等级 ---
get_risk_level() {
    local score=$1
    if [ "$score" -ge 80 ]; then
        echo "critical"
    elif [ "$score" -ge 50 ]; then
        echo "high"
    elif [ "$score" -ge 30 ]; then
        echo "medium"
    else
        echo "low"
    fi
}

# --- 执行风控动作 ---
execute_action() {
    local risk_score=$1
    local action_taken="none"

    if [ "$risk_score" -ge "$RISK_THRESHOLD" ]; then
        case "$ACTION" in
            "warn")
                log_warn "高风险 IP 检测！风险分数: ${risk_score}，仅发出告警"
                action_taken="warned"
                ;;
            "disconnect")
                log_warn "高风险 IP 检测！风险分数: ${risk_score}，执行断网"
                # 断开 WAN 连接
                ifdown wan 2>/dev/null
                sleep 5
                ifup wan 2>/dev/null
                action_taken="disconnected_reconnected"
                ;;
            "switch_proxy")
                log_warn "高风险 IP 检测！风险分数: ${risk_score}，尝试切换代理节点"
                # 通知 Passwall 切换节点 (如果可用)
                if [ -f "/usr/share/passwall/rule_update.lua" ]; then
                    # 触发 Passwall 切换节点
                    /etc/init.d/passwall restart 2>/dev/null
                    action_taken="proxy_switched"
                else
                    log_err "Passwall 不可用，无法切换代理"
                    action_taken="switch_failed"
                fi
                ;;
            *)
                log_info "未知动作: ${ACTION}"
                action_taken="unknown_action"
                ;;
        esac
    else
        log_info "IP 风险分数: ${risk_score}，低于阈值 ${RISK_THRESHOLD}，无需操作"
    fi

    echo "$action_taken"
}

# --- 主检测循环 ---
run_check() {
    load_config

    if [ "$ENABLED" != "1" ]; then
        log_info "风控服务已禁用"
        echo '{"status":"disabled","timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'"}' > "$STATUS_FILE"
        return 0
    fi

    local wan_ip=$(get_wan_ip)
    if [ -z "$wan_ip" ]; then
        log_err "无法获取 WAN IP"
        echo '{"error":"cannot_get_wan_ip","timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'"}' > "$STATUS_FILE"
        return 1
    fi

    log_info "开始检测 WAN IP: ${wan_ip}"

    # 执行检测
    local check_result=""
    case "$API_PROVIDER" in
        "ip-api"|*)
            check_result=$(check_ip_risk_ipapi "$wan_ip")
            ;;
    esac

    if [ -z "$check_result" ]; then
        log_err "检测失败"
        return 1
    fi

    # 获取风险分数
    local risk_score=$(echo "$check_result" | jsonfilter -e '@.risk_score' 2>/dev/null || echo "0")

    # 执行相应动作
    local action=$(execute_action "$risk_score")

    # 更新动作字段并保存状态
    echo "$check_result" | sed "s/\"action_taken\": \"none\"/\"action_taken\": \"${action}\"/" > "$STATUS_FILE"

    log_info "检测完成，风险分数: ${risk_score}，动作: ${action}"
}

# --- 守护循环 ---
daemon_loop() {
    log_info "CB-Shield 风控服务启动 (间隔: ${CHECK_INTERVAL}s)"
    
    # 确保 Kill Switch 过滤链存在
    nft list chain inet fw4 cb_shield_killswitch >/dev/null 2>&1 || nft add chain inet fw4 cb_shield_killswitch { type filter hook forward priority -1 \; } 2>/dev/null
    nft flush chain inet fw4 cb_shield_killswitch 2>/dev/null

    while true; do
        # ========== 流量锁 Kill Switch (V2.2 Gold 特性) ==========
        # 利用 -m 绝对超时探测代理节点连通性
        if ! curl -I -s --connect-timeout 3 -m 3 https://www.google.com > /dev/null; then
            # 节点掉线，触发流量锁，阻断网卡转发
            nft flush chain inet fw4 cb_shield_killswitch 2>/dev/null
            nft add rule inet fw4 cb_shield_killswitch reject 2>/dev/null
            log_warn "流量锁已触发：代理断线，已强制物理切断内网转发，绝杀裸连泄露！"
        else
            # 节点恢复，解除流量锁
            nft flush chain inet fw4 cb_shield_killswitch 2>/dev/null
        fi
        # ======================================================

        # 防止重入
        if [ -f "$LOCK_FILE" ]; then
            log_warn "上一次检测仍在运行，跳过"
        else
            touch "$LOCK_FILE"
            run_check
            rm -f "$LOCK_FILE"
        fi
        sleep "$CHECK_INTERVAL"
    done
}

# --- 单次运行 ---
run_once() {
    load_config
    touch "$LOCK_FILE"
    run_check
    rm -f "$LOCK_FILE"
}

# --- 入口 ---
case "$1" in
    "daemon")
        load_config
        daemon_loop
        ;;
    "check")
        run_once
        ;;
    "status")
        if [ -f "$STATUS_FILE" ]; then
            cat "$STATUS_FILE"
        else
            echo '{"status":"no_data"}'
        fi
        ;;
    *)
        echo "用法: $0 {daemon|check|status}"
        echo "  daemon - 后台守护运行"
        echo "  check  - 单次检测"
        echo "  status - 查看状态"
        exit 1
        ;;
esac

exit 0
