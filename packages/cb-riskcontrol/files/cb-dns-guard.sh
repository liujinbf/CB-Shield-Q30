#!/bin/sh

STATUS_FILE="/tmp/cb-dns-health.json"

read_cfg() {
    ENABLED="$(uci -q get cb-dns-guard.main.enabled || echo 1)"
    INTERVAL="$(uci -q get cb-dns-guard.main.interval || echo 120)"
    ENFORCE_HIJACK="$(uci -q get cb-dns-guard.main.enforce_shop_dns_hijack || echo 1)"
    REQUIRE_DOH_DOT="$(uci -q get cb-dns-guard.main.require_doh_dot || echo 0)"
}

redirect_exists() {
    local name="$1"
    uci -q show firewall | grep -q "name='$name'"
}

create_redirect() {
    local shop="$1"
    local proto="$2"
    local name="Hijack-${shop}-DNS-$(echo "$proto" | tr 'a-z' 'A-Z')"
    local sid

    sid="$(uci add firewall redirect)" || return 1
    uci -q set firewall."$sid".name="$name"
    uci -q set firewall."$sid".src="$shop"
    uci -q set firewall."$sid".proto="$proto"
    uci -q set firewall."$sid".src_dport='53'
    uci -q set firewall."$sid".dest_port='53'
    uci -q set firewall."$sid".target='DNAT'
    return 0
}

ensure_shop_redirects() {
    local proto="$1"
    local shop name changed=0 all_ok=1

    for shop in shop1 shop2 shop3 shop4 shop5; do
        name="Hijack-${shop}-DNS-$(echo "$proto" | tr 'a-z' 'A-Z')"
        if ! redirect_exists "$name"; then
            if [ "$ENFORCE_HIJACK" = "1" ]; then
                create_redirect "$shop" "$proto" || all_ok=0
                changed=1
                /usr/bin/cb-eventlog write dns "created firewall redirect ${name}"
            else
                all_ok=0
            fi
        fi
    done

    if [ "$changed" = "1" ]; then
        uci -q commit firewall
        /etc/init.d/firewall reload >/dev/null 2>&1
    fi

    [ "$all_ok" = "1" ] && echo "true" || echo "false"
}

service_running() {
    [ -x "/etc/init.d/$1" ] && /etc/init.d/"$1" status >/dev/null 2>&1
}

run_once() {
    local udp_ok tcp_ok dohdot_ok health note
    read_cfg

    if [ "$ENABLED" != "1" ]; then
        echo '{"timestamp":"'"$(date '+%Y-%m-%d %H:%M:%S')"'","health":"disabled"}' > "$STATUS_FILE"
        return
    fi

    udp_ok="$(ensure_shop_redirects udp)"
    tcp_ok="$(ensure_shop_redirects tcp)"

    if service_running https-dns-proxy || service_running smartdns; then
        dohdot_ok="true"
    else
        dohdot_ok="false"
    fi

    health="green"
    note="ok"
    if [ "$udp_ok" != "true" ] || [ "$tcp_ok" != "true" ]; then
        health="red"
        note="dns_hijack_missing"
    elif [ "$REQUIRE_DOH_DOT" = "1" ] && [ "$dohdot_ok" != "true" ]; then
        health="yellow"
        note="doh_dot_not_running"
    fi

    cat > "$STATUS_FILE" <<EOF
{
  "timestamp":"$(date '+%Y-%m-%d %H:%M:%S')",
  "health":"$health",
  "note":"$note",
  "udp_hijack":$udp_ok,
  "tcp_hijack":$tcp_ok,
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
