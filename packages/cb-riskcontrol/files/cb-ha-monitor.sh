#!/bin/sh

STATUS_FILE="/tmp/cb-ha.json"
STATE_FILE="/tmp/cb-ha.state"

read_cfg() {
    ENABLED="$(uci -q get cb-ha.main.enabled || echo 1)"
    INTERVAL="$(uci -q get cb-ha.main.interval || echo 20)"
    FAIL_THRESHOLD="$(uci -q get cb-ha.main.fail_threshold || echo 3)"
    COOLDOWN="$(uci -q get cb-ha.main.cooldown || echo 90)"
    TEST_URL="$(uci -q get cb-ha.main.test_url || echo https://www.gstatic.com/generate_204)"
    ACTION="$(uci -q get cb-ha.main.action || echo restart_proxy)"
}

service_exists() {
    [ -x "/etc/init.d/$1" ]
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

load_state() {
    FAIL_COUNT=0
    LAST_SWITCH=0
    [ -f "$STATE_FILE" ] && . "$STATE_FILE"
}

save_state() {
    cat > "$STATE_FILE" <<EOF
FAIL_COUNT=$FAIL_COUNT
LAST_SWITCH=$LAST_SWITCH
EOF
}

write_status() {
    local health="$1"
    local note="$2"
    local proxy_service="$3"
    cat > "$STATUS_FILE" <<EOF
{
  "timestamp":"$(date '+%Y-%m-%d %H:%M:%S')",
  "health":"$health",
  "fail_count":$FAIL_COUNT,
  "last_switch":$LAST_SWITCH,
  "action":"$ACTION",
  "proxy_service":"$proxy_service",
  "note":"$note"
}
EOF
}

run_once() {
    local now delta proxy_service
    read_cfg
    load_state
    proxy_service="$(find_proxy_service)"

    if [ "$ENABLED" != "1" ]; then
        write_status "disabled" "ha_monitor_disabled" "$proxy_service"
        return 0
    fi

    if curl -I -s --connect-timeout 4 -m 5 "$TEST_URL" >/dev/null 2>&1; then
        if [ "$FAIL_COUNT" -ne 0 ]; then
            /usr/bin/cb-eventlog write ha "link recovered, fail_count reset"
        fi
        FAIL_COUNT=0
        save_state
        write_status "healthy" "probe_ok" "$proxy_service"
        return 0
    fi

    FAIL_COUNT=$((FAIL_COUNT + 1))
    now="$(date +%s)"
    delta=$((now - LAST_SWITCH))

    if [ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ]; then
        if [ "$delta" -lt "$COOLDOWN" ]; then
            write_status "tripped" "circuit_open" "$proxy_service"
            save_state
            return 0
        fi

        case "$ACTION" in
            restart_proxy|restart_passwall)
                if [ -n "$proxy_service" ]; then
                    /etc/init.d/"$proxy_service" restart >/dev/null 2>&1
                    /usr/bin/cb-eventlog write ha "proxy service restarted by ha monitor: $proxy_service"
                else
                    /usr/bin/cb-eventlog write ha "proxy service not found, restart skipped"
                fi
                ;;
            *)
                /usr/bin/cb-eventlog write ha "unknown ha action: $ACTION"
                ;;
        esac
        LAST_SWITCH="$now"
        FAIL_COUNT=0
        save_state
        write_status "recovering" "ha_action_executed" "$proxy_service"
        return 0
    fi

    save_state
    write_status "degraded" "probe_failed" "$proxy_service"
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
        [ -f "$STATUS_FILE" ] && cat "$STATUS_FILE" || echo '{"health":"no_data"}'
        ;;
    *)
        echo "usage: $0 {check|daemon|status}"
        exit 1
        ;;
esac

exit 0
