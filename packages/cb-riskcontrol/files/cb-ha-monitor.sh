#!/bin/sh

STATUS_FILE="/tmp/cb-ha.json"
STATE_FILE="/tmp/cb-ha.state"

read_cfg() {
    ENABLED="$(uci -q get cb-ha.main.enabled || echo 1)"
    INTERVAL="$(uci -q get cb-ha.main.interval || echo 20)"
    FAIL_THRESHOLD="$(uci -q get cb-ha.main.fail_threshold || echo 3)"
    COOLDOWN="$(uci -q get cb-ha.main.cooldown || echo 90)"
    TEST_URL="$(uci -q get cb-ha.main.test_url || echo https://www.gstatic.com/generate_204)"
    ACTION="$(uci -q get cb-ha.main.action || echo restart_passwall)"
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
    cat > "$STATUS_FILE" <<EOF
{
  "timestamp":"$(date '+%Y-%m-%d %H:%M:%S')",
  "health":"$health",
  "fail_count":$FAIL_COUNT,
  "last_switch":$LAST_SWITCH,
  "action":"$ACTION",
  "note":"$note"
}
EOF
}

run_once() {
    local now delta
    read_cfg
    load_state

    if [ "$ENABLED" != "1" ]; then
        write_status "disabled" "ha_monitor_disabled"
        return 0
    fi

    if curl -I -s --connect-timeout 4 -m 5 "$TEST_URL" >/dev/null 2>&1; then
        if [ "$FAIL_COUNT" -ne 0 ]; then
            /usr/bin/cb-eventlog write ha "link recovered, fail_count reset"
        fi
        FAIL_COUNT=0
        save_state
        write_status "healthy" "probe_ok"
        return 0
    fi

    FAIL_COUNT=$((FAIL_COUNT + 1))
    now="$(date +%s)"
    delta=$((now - LAST_SWITCH))

    if [ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ]; then
        if [ "$delta" -lt "$COOLDOWN" ]; then
            write_status "tripped" "circuit_open"
            save_state
            return 0
        fi

        case "$ACTION" in
            restart_passwall)
                if [ -x /etc/init.d/passwall ]; then
                    /etc/init.d/passwall restart >/dev/null 2>&1
                    /usr/bin/cb-eventlog write ha "passwall restarted by ha monitor"
                else
                    /usr/bin/cb-eventlog write ha "passwall service not found, restart skipped"
                fi
                ;;
            *)
                /usr/bin/cb-eventlog write ha "unknown ha action: $ACTION"
                ;;
        esac
        LAST_SWITCH="$now"
        FAIL_COUNT=0
        save_state
        write_status "recovering" "ha_action_executed"
        return 0
    fi

    save_state
    write_status "degraded" "probe_failed"
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
