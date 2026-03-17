#!/bin/sh

STATUS_FILE="/tmp/cb-health.json"

read_cfg() {
    ENABLED="$(uci -q get cb-health.main.enabled || echo 1)"
    AUTO_REPAIR="$(uci -q get cb-health.main.auto_repair || echo 1)"
    INTERVAL="$(uci -q get cb-health.main.interval || echo 60)"
    CHECK_PASSWALL="$(uci -q get cb-health.main.check_passwall || echo 1)"
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

ensure_wifi() {
    local ok="true"
    local action="none"
    local radio0_disabled radio1_disabled

    if [ "$CHECK_WIFI" != "1" ]; then
        echo "true|skipped"
        return
    fi

    radio0_disabled="$(uci -q get wireless.radio0.disabled || echo 1)"
    radio1_disabled="$(uci -q get wireless.radio1.disabled || echo 1)"

    if [ "$radio0_disabled" = "1" ] || [ "$radio1_disabled" = "1" ]; then
        ok="false"
        if [ "$AUTO_REPAIR" = "1" ]; then
            uci -q set wireless.radio0.disabled='0'
            uci -q set wireless.radio1.disabled='0'
            uci -q set wireless.default_radio0.disabled='0'
            uci -q set wireless.default_radio1.disabled='0'
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
    local passwall="$2"
    local risk="$3"
    local portal="$4"
    local wifi="$5"
    local overall="$6"

    cat > "$STATUS_FILE" <<EOF
{
  "timestamp": "$ts",
  "overall": "$overall",
  "passwall": {"present": ${passwall%%|*}, "running": $(echo "$passwall" | cut -d'|' -f2), "action": "$(echo "$passwall" | cut -d'|' -f3)"},
  "riskcontrol": {"present": ${risk%%|*}, "running": $(echo "$risk" | cut -d'|' -f2), "action": "$(echo "$risk" | cut -d'|' -f3)"},
  "portal": {"present": ${portal%%|*}, "running": $(echo "$portal" | cut -d'|' -f2), "action": "$(echo "$portal" | cut -d'|' -f3)"},
  "wifi": {"healthy": ${wifi%%|*}, "action": "$(echo "$wifi" | cut -d'|' -f2)"}
}
EOF
}

run_once() {
    local ts overall
    local passwall_state risk_state portal_state wifi_state

    read_cfg
    if [ "$ENABLED" != "1" ]; then
        cat > "$STATUS_FILE" <<EOF
{"timestamp":"$(date '+%Y-%m-%d %H:%M:%S')","overall":"disabled"}
EOF
        exit 0
    fi

    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    passwall_state="$(ensure_service passwall "$CHECK_PASSWALL")"
    risk_state="$(ensure_service cb-riskcontrol "$CHECK_RISKCONTROL")"
    portal_state="$(ensure_service cb-portal "$CHECK_PORTAL")"
    wifi_state="$(ensure_wifi)"

    overall="ok"
    echo "$passwall_state" | grep -q "|false|" && overall="degraded"
    echo "$risk_state" | grep -q "|false|" && overall="degraded"
    echo "$portal_state" | grep -q "|false|" && overall="degraded"
    echo "$wifi_state" | grep -q "^false|" && overall="degraded"

    build_status_json "$ts" "$passwall_state" "$risk_state" "$portal_state" "$wifi_state" "$overall"
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
