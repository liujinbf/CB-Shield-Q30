#!/bin/sh

STATUS_FILE="/tmp/cb-dns-health.json"

read_cfg() {
    ENABLED="$(uci -q get cb-dns-guard.main.enabled || echo 1)"
    INTERVAL="$(uci -q get cb-dns-guard.main.interval || echo 120)"
    REQUIRE_DOH_DOT="$(uci -q get cb-dns-guard.main.require_doh_dot || echo 0)"
}

service_running() {
    [ -x "/etc/init.d/$1" ] && /etc/init.d/"$1" status >/dev/null 2>&1
}

run_once() {
    local dns_ok dohdot_ok health note
    read_cfg

    if [ "$ENABLED" != "1" ]; then
        echo '{"timestamp":"'"$(date '+%Y-%m-%d %H:%M:%S')"'","health":"disabled"}' > "$STATUS_FILE"
        return
    fi

    if service_running dnsmasq; then
        dns_ok="true"
    else
        dns_ok="false"
    fi

    if service_running https-dns-proxy || service_running smartdns; then
        dohdot_ok="true"
    else
        dohdot_ok="false"
    fi

    health="green"
    note="single_network_mode"
    if [ "$dns_ok" != "true" ]; then
        health="red"
        note="dnsmasq_not_running"
    elif [ "$REQUIRE_DOH_DOT" = "1" ] && [ "$dohdot_ok" != "true" ]; then
        health="yellow"
        note="doh_dot_not_running"
    fi

    cat > "$STATUS_FILE" <<EOF
{
  "timestamp":"$(date '+%Y-%m-%d %H:%M:%S')",
  "health":"$health",
  "note":"$note",
  "dnsmasq_running":$dns_ok,
  "doh_dot_running":$dohdot_ok
}
EOF
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
