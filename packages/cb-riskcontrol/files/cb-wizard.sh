#!/bin/sh

STATUS_FILE="/tmp/cb-wizard.json"
WIZARD_FLAG="/etc/cbshield/wizard_required"
WIZARD_DONE="/etc/cbshield/wizard_done"

need_password_change() {
    local shadow_line hash
    shadow_line="$(grep '^root:' /etc/shadow 2>/dev/null)"
    hash="$(echo "$shadow_line" | cut -d: -f2)"

    # empty hash or known default placeholders should force change
    [ -z "$hash" ] && return 0
    [ "$hash" = "*" ] && return 0
    [ "$hash" = "!" ] && return 0
    return 1
}

wizard_required() {
    local cfg_required
    cfg_required="$(uci -q get cb-wizard.main.required || echo 1)"
    [ "$cfg_required" = "1" ] || return 1
    [ -f "$WIZARD_FLAG" ] && return 0
    need_password_change && return 0
    return 1
}

write_status() {
    local required="$1"
    local need_change="false"
    if need_password_change; then
        need_change="true"
    fi
    cat > "$STATUS_FILE" <<EOF
{
  "timestamp":"$(date '+%Y-%m-%d %H:%M:%S')",
  "required":$required,
  "done":$([ -f "$WIZARD_DONE" ] && echo true || echo false),
  "need_password_change":$need_change
}
EOF
}

apply_wizard() {
    local pass="$1"
    local timezone="$2"
    local zonename="$3"
    local wan_proto="$4"
    local wan_user="$5"
    local wan_pass="$6"
    local office_ssid="$7"
    local office_key="$8"
    local office5_ssid="$9"

    [ -n "$pass" ] || {
        echo '{"status":"error","message":"password_required"}'
        return 1
    }
    if [ "${#pass}" -lt 8 ]; then
        echo '{"status":"error","message":"password_too_short"}'
        return 1
    fi

    echo "root:$pass" | chpasswd || {
        echo '{"status":"error","message":"password_set_failed"}'
        return 1
    }

    [ -n "$timezone" ] && uci -q set system.@system[0].timezone="$timezone"
    [ -n "$zonename" ] && uci -q set system.@system[0].zonename="$zonename"
    uci commit system

    case "$wan_proto" in
        dhcp|pppoe|static) uci -q set network.wan.proto="$wan_proto" ;;
        *) wan_proto="dhcp"; uci -q set network.wan.proto='dhcp' ;;
    esac
    if [ "$wan_proto" = "pppoe" ]; then
        uci -q set network.wan.username="$wan_user"
        uci -q set network.wan.password="$wan_pass"
    fi
    uci commit network

    [ -n "$office_ssid" ] && uci -q set wireless.office_24g.ssid="$office_ssid"
    [ -n "$office_key" ] && {
        uci -q set wireless.office_24g.key="$office_key"
        uci -q set wireless.office_5g.key="$office_key"
    }
    [ -n "$office5_ssid" ] && uci -q set wireless.office_5g.ssid="$office5_ssid"
    uci commit wireless

    /etc/init.d/network restart >/dev/null 2>&1
    wifi reload >/dev/null 2>&1

    mkdir -p /etc/cbshield
    rm -f "$WIZARD_FLAG"
    touch "$WIZARD_DONE"
    uci -q set cb-wizard.main.required='0'
    uci commit cb-wizard

    /usr/bin/cb-eventlog write wizard "first boot wizard applied"
    echo '{"status":"ok"}'
    return 0
}

case "$1" in
    status)
        if wizard_required; then
            write_status true
        else
            write_status false
        fi
        cat "$STATUS_FILE"
        ;;
    apply)
        shift
        apply_wizard "$@"
        ;;
    force)
        mkdir -p /etc/cbshield
        touch "$WIZARD_FLAG"
        uci -q set cb-wizard.main.required='1'
        uci commit cb-wizard
        echo '{"status":"ok","required":true}'
        ;;
    *)
        echo "usage: $0 {status|apply <pass> <timezone> <zonename> <wan_proto> <wan_user> <wan_pass> <office_ssid> <office_key> <office5_ssid>|force}"
        exit 1
        ;;
esac

exit 0
