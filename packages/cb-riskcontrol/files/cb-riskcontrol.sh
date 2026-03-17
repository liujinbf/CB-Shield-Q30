#!/bin/sh
# CB-Shield IP risk control daemon

STATUS_FILE="/tmp/cb-riskcontrol.json"
LOCK_FILE="/tmp/cb-riskcontrol.lock"
LOG_TAG="cb-riskcontrol"

ENABLED=1
CHECK_INTERVAL=300
ACTION="warn"
RISK_THRESHOLD=70
API_PROVIDER="ip-api"

log_info() {
    logger -t "$LOG_TAG" -p daemon.info "$1"
}

log_warn() {
    logger -t "$LOG_TAG" -p daemon.warn "$1"
}

log_err() {
    logger -t "$LOG_TAG" -p daemon.err "$1"
}

load_config() {
    ENABLED="$(uci -q get cb-riskcontrol.main.enabled || echo 1)"
    CHECK_INTERVAL="$(uci -q get cb-riskcontrol.main.check_interval || echo 300)"
    ACTION="$(uci -q get cb-riskcontrol.main.action || echo warn)"
    RISK_THRESHOLD="$(uci -q get cb-riskcontrol.main.risk_threshold || echo 70)"
    API_PROVIDER="$(uci -q get cb-riskcontrol.main.api_provider || echo ip-api)"
}

get_wan_ip() {
    local wan_json
    local ip

    wan_json="$(ubus call network.interface.wan status 2>/dev/null)"
    ip="$(echo "$wan_json" | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)"

    if [ -z "$ip" ]; then
        ip="$(curl -s --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null)"
    fi
    echo "$ip"
}

get_risk_level() {
    local score="$1"
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

check_ip_risk_ipapi() {
    local ip="$1"
    local result
    local is_proxy
    local is_hosting
    local country
    local isp
    local org
    local asn
    local city
    local timezone
    local current_zone
    local risk_score=0
    local risk_factors=""

    result="$(curl -s --connect-timeout 10 --max-time 15 \
        "http://ip-api.com/json/${ip}?fields=status,message,country,countryCode,region,city,isp,org,as,proxy,hosting,timezone,query" \
        2>/dev/null)"

    if [ -z "$result" ]; then
        echo '{"error":"api_request_failed","risk_score":0}'
        return 1
    fi

    is_proxy="$(echo "$result" | jsonfilter -e '@.proxy' 2>/dev/null)"
    is_hosting="$(echo "$result" | jsonfilter -e '@.hosting' 2>/dev/null)"
    country="$(echo "$result" | jsonfilter -e '@.country' 2>/dev/null)"
    isp="$(echo "$result" | jsonfilter -e '@.isp' 2>/dev/null)"
    org="$(echo "$result" | jsonfilter -e '@.org' 2>/dev/null)"
    asn="$(echo "$result" | jsonfilter -e '@.as' 2>/dev/null)"
    city="$(echo "$result" | jsonfilter -e '@.city' 2>/dev/null)"
    timezone="$(echo "$result" | jsonfilter -e '@.timezone' 2>/dev/null)"

    if [ -n "$timezone" ] && [ "$timezone" != "null" ]; then
        current_zone="$(uci -q get system.@system[0].zonename)"
        if [ "$timezone" != "$current_zone" ]; then
            log_info "timezone changed: $current_zone -> $timezone"
            uci set system.@system[0].zonename="$timezone"
            uci commit system
            /etc/init.d/system reload
        fi
    fi

    if [ "$is_proxy" = "true" ]; then
        risk_score=$((risk_score + 50))
        risk_factors="${risk_factors}proxy_detected,"
    fi

    if [ "$is_hosting" = "true" ]; then
        risk_score=$((risk_score + 30))
        risk_factors="${risk_factors}hosting_ip,"
    fi

    echo "$org $isp" | grep -qiE "vpn|proxy|tunnel|tor|hosting|cloud|server|data.?center|cdn" && {
        risk_score=$((risk_score + 20))
        risk_factors="${risk_factors}suspicious_org,"
    }

    cat <<EOF
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
  "risk_level": "$(get_risk_level "$risk_score")",
  "risk_factors": "${risk_factors%,}",
  "action_taken": "none"
}
EOF
}

execute_action() {
    local risk_score="$1"
    local action_taken="none"

    if [ "$risk_score" -ge "$RISK_THRESHOLD" ]; then
        case "$ACTION" in
            warn)
                log_warn "high risk ip detected: score=${risk_score}, action=warn"
                action_taken="warned"
                ;;
            disconnect)
                log_warn "high risk ip detected: score=${risk_score}, action=disconnect"
                ifdown wan 2>/dev/null
                sleep 5
                ifup wan 2>/dev/null
                action_taken="disconnected_reconnected"
                ;;
            switch_proxy)
                log_warn "high risk ip detected: score=${risk_score}, action=switch_proxy"
                if [ -f "/etc/init.d/passwall" ]; then
                    /etc/init.d/passwall restart 2>/dev/null
                    action_taken="proxy_switched"
                else
                    log_err "passwall not found"
                    action_taken="switch_failed"
                fi
                ;;
            *)
                log_warn "unknown action: ${ACTION}"
                action_taken="unknown_action"
                ;;
        esac
    else
        log_info "risk score ${risk_score} below threshold ${RISK_THRESHOLD}"
    fi

    echo "$action_taken"
}

run_check() {
    local wan_ip
    local check_result
    local risk_score
    local action

    load_config

    if [ "$ENABLED" != "1" ]; then
        echo '{"status":"disabled","timestamp":"'"$(date '+%Y-%m-%d %H:%M:%S')"'"}' > "$STATUS_FILE"
        return 0
    fi

    wan_ip="$(get_wan_ip)"
    if [ -z "$wan_ip" ]; then
        log_err "cannot get wan ip"
        echo '{"error":"cannot_get_wan_ip","timestamp":"'"$(date '+%Y-%m-%d %H:%M:%S')"'"}' > "$STATUS_FILE"
        return 1
    fi

    case "$API_PROVIDER" in
        ip-api|*)
            check_result="$(check_ip_risk_ipapi "$wan_ip")"
            ;;
    esac

    if [ -z "$check_result" ]; then
        log_err "risk check failed"
        return 1
    fi

    risk_score="$(echo "$check_result" | jsonfilter -e '@.risk_score' 2>/dev/null || echo 0)"
    action="$(execute_action "$risk_score")"

    echo "$check_result" | sed "s/\"action_taken\": \"none\"/\"action_taken\": \"${action}\"/" > "$STATUS_FILE"
}

ensure_killswitch_chain() {
    nft list chain inet fw4 cb_shield_killswitch >/dev/null 2>&1 || \
    nft add chain inet fw4 cb_shield_killswitch "{ type filter hook forward priority -1; }" >/dev/null 2>&1
}

enable_killswitch() {
    local i
    ensure_killswitch_chain
    nft flush chain inet fw4 cb_shield_killswitch >/dev/null 2>&1
    for i in 1 2 3 4 5; do
        nft add rule inet fw4 cb_shield_killswitch iifname "shop${i}" reject >/dev/null 2>&1
    done
}

disable_killswitch() {
    ensure_killswitch_chain
    nft flush chain inet fw4 cb_shield_killswitch >/dev/null 2>&1
}

daemon_loop() {
    load_config
    log_info "risk daemon started, interval=${CHECK_INTERVAL}s"
    ensure_killswitch_chain
    disable_killswitch

    while true; do
        if ! curl -I -s --connect-timeout 3 -m 3 https://www.google.com >/dev/null 2>&1; then
            enable_killswitch
            log_warn "killswitch enabled because upstream is unreachable"
        else
            disable_killswitch
        fi

        if [ -f "$LOCK_FILE" ]; then
            log_warn "skip check because previous run still active"
        else
            touch "$LOCK_FILE"
            run_check
            rm -f "$LOCK_FILE"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

run_once() {
    touch "$LOCK_FILE"
    run_check
    rm -f "$LOCK_FILE"
}

case "$1" in
    daemon)
        daemon_loop
        ;;
    check)
        run_once
        ;;
    status)
        if [ -f "$STATUS_FILE" ]; then
            cat "$STATUS_FILE"
        else
            echo '{"status":"no_data"}'
        fi
        ;;
    *)
        echo "usage: $0 {daemon|check|status}"
        exit 1
        ;;
esac

exit 0
