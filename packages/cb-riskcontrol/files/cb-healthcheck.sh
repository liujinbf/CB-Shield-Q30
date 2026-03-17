#!/bin/sh

STATUS_FILE="/tmp/cb-health.json"

read_cfg() {
    ENABLED="$(uci -q get cb-health.main.enabled || echo 1)"
    AUTO_REPAIR="$(uci -q get cb-health.main.auto_repair || echo 1)"
    INTERVAL="$(uci -q get cb-health.main.interval || echo 60)"
    CHECK_PROXY="$(uci -q get cb-health.main.check_proxy || uci -q get cb-health.main.check_passwall || echo 1)"
    CHECK_RISKCONTROL="$(uci -q get cb-health.main.check_riskcontrol || echo 1)"
    CHECK_PORTAL="$(uci -q get cb-health.main.check_portal || echo 1)"
    CHECK_WIFI="$(uci -q get cb-health.main.check_wifi || echo 1)"
}

service_exists() {
    [ -x "/etc/init.d/$1" ]
}

service_running() {
    local name="$1"
    /etc/init.d/"$name" status >/dev/null 2>&1
}

find_proxy_service() {
    if service_exists openclash; then
        echo "openclash"
    elif service_exists passwall; then
        echo "passwall"
    else
        echo ""
    fi
}

ensure_service() {
    local name="$1"
    local check_enabled="$2"
    local present="false"
    local running="false"
    local action="none"

    if [ "$check_enabled" != "1" ]; then
        echo "$present|$running|skipped"
        return
    fi

    if service_exists "$name"; then
        present="true"
        if service_running "$name"; then
            running="true"
        elif [ "$AUTO_REPAIR" = "1" ]; then
            /etc/init.d/"$name" enable >/dev/null 2>&1
            /etc/init.d/"$name" start >/dev/null 2>&1
            if service_running "$name"; then
                running="true"
                action="started"
                /usr/bin/cb-eventlog write health "service $name started by auto-repair"
            else
                action="start_failed"
            fi
        fi
    fi

    echo "$present|$running|$action"
}

ensure_proxy() {
    local proxy_service
    proxy_service="$(find_proxy_service)"
    if [ -z "$proxy_service" ]; then
        echo "false|false|not_installed|none"
        return
    fi

    printf '%s|%s\n' "$(ensure_service "$proxy_service" "$CHECK_PROXY")" "$proxy_service"
}

ensure_wifi() {
    local ok="true"
    local action="none"
    local radio0_exists radio1_exists radio0_disabled radio1_disabled

    if [ "$CHECK_WIFI" != "1" ]; then
        echo "true|skipped"
        return
    fi

    radio0_exists="0"
    radio1_exists="0"
    uci -q get wireless.radio0 >/dev/null 2>&1 && radio0_exists="1"
    uci -q get wireless.radio1 >/dev/null 2>&1 && radio1_exists="1"

    radio0_disabled="0"
    radio1_disabled="0"
    [ "$radio0_exists" = "1" ] && radio0_disabled="$(uci -q get wireless.radio0.disabled || echo 1)"
    [ "$radio1_exists" = "1" ] && radio1_disabled="$(uci -q get wireless.radio1.disabled || echo 1)"

    if { [ "$radio0_exists" = "1" ] && [ "$radio0_disabled" = "1" ]; } || \
       { [ "$radio1_exists" = "1" ] && [ "$radio1_disabled" = "1" ]; }; then
        ok="false"
        if [ "$AUTO_REPAIR" = "1" ]; then
            [ "$radio0_exists" = "1" ] && {
                uci -q set wireless.radio0.disabled='0'
                uci -q set wireless.default_radio0.disabled='0'
            }
            [ "$radio1_exists" = "1" ] && {
                uci -q set wireless.radio1.disabled='0'
                uci -q set wireless.default_radio1.disabled='0'
            }
            uci commit wireless
            wifi reload >/dev/null 2>&1
            ok="true"
            action="wifi_reloaded"
            /usr/bin/cb-eventlog write health "wifi radios re-enabled by auto-repair"
        fi
    fi

    echo "$ok|$action"
}

build_status_json() {
    local ts="$1"
    local proxy="$2"
    local risk="$3"
    local portal="$4"
    local wifi="$5"
    local overall="$6"
    local proxy_present proxy_running proxy_action proxy_name

    proxy_present="$(echo "$proxy" | cut -d'|' -f1)"
    proxy_running="$(echo "$proxy" | cut -d'|' -f2)"
    proxy_action="$(echo "$proxy" | cut -d'|' -f3)"
    proxy_name="$(echo "$proxy" | cut -d'|' -f4)"

    cat > "$STATUS_FILE" <<EOF
{
  "timestamp": "$ts",
  "overall": "$overall",
  "proxy": {"present": ${proxy_present}, "running": ${proxy_running}, "action": "${proxy_action}", "service": "${proxy_name}"},
  "riskcontrol": {"present": ${risk%%|*}, "running": $(echo "$risk" | cut -d'|' -f2), "action": "$(echo "$risk" | cut -d'|' -f3)"},
  "portal": {"present": ${portal%%|*}, "running": $(echo "$portal" | cut -d'|' -f2), "action": "$(echo "$portal" | cut -d'|' -f3)"},
  "wifi": {"healthy": ${wifi%%|*}, "action": "$(echo "$wifi" | cut -d'|' -f2)"}
}
EOF
}

run_once() {
    local ts overall
    local proxy_state risk_state portal_state wifi_state

    read_cfg
    if [ "$ENABLED" != "1" ]; then
        cat > "$STATUS_FILE" <<EOF
{"timestamp":"$(date '+%Y-%m-%d %H:%M:%S')","overall":"disabled"}
EOF
        return 0
    fi

    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    proxy_state="$(ensure_proxy)"
    risk_state="$(ensure_service cb-riskcontrol "$CHECK_RISKCONTROL")"
    portal_state="$(ensure_service cb-portal "$CHECK_PORTAL")"
    wifi_state="$(ensure_wifi)"

    overall="ok"
    echo "$proxy_state" | grep -q "|false|" && overall="degraded"
    echo "$risk_state" | grep -q "|false|" && overall="degraded"
    echo "$portal_state" | grep -q "|false|" && overall="degraded"
    echo "$wifi_state" | grep -q "^false|" && overall="degraded"

    build_status_json "$ts" "$proxy_state" "$risk_state" "$portal_state" "$wifi_state" "$overall"
}

daemon_loop() {
    while true; do
        run_once
        read_cfg
        sleep "$INTERVAL"
    done
}

case "$1" in
    check)
        run_once
        ;;
    daemon)
        daemon_loop
        ;;
    status)
        [ -f "$STATUS_FILE" ] && cat "$STATUS_FILE" || echo '{"overall":"no_data"}'
        ;;
    *)
        echo "usage: $0 {check|daemon|status}"
        exit 1
        ;;
esac

exit 0
