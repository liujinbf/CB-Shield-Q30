#!/bin/sh

STATUS_FILE="/tmp/cb-policy.json"

read_global_cfg() {
    ENABLED="$(uci -q get cb-policy.global.enabled || echo 1)"
    INTERVAL="$(uci -q get cb-policy.global.interval || echo 300)"
}

num_or_zero() {
    local n="$1"
    case "$n" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$n" ;;
    esac
}

json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

to_minutes() {
    local hm="$1"
    local h m
    h="$(echo "$hm" | cut -d: -f1)"
    m="$(echo "$hm" | cut -d: -f2)"
    h="$(num_or_zero "$h")"
    m="$(num_or_zero "$m")"
    echo $((h * 60 + m))
}

is_now_in_range() {
    local begin="$1"
    local end="$2"
    local now_m begin_m end_m

    now_m="$(to_minutes "$(date '+%H:%M')")"
    begin_m="$(to_minutes "$begin")"
    end_m="$(to_minutes "$end")"

    if [ "$begin_m" -le "$end_m" ]; then
        [ "$now_m" -ge "$begin_m" ] && [ "$now_m" -le "$end_m" ]
        return $?
    fi

    # 跨天窗口，例如 23:00-07:00
    [ "$now_m" -ge "$begin_m" ] || [ "$now_m" -le "$end_m" ]
}

apply_runtime_state() {
    local shop="$1"
    local enable="$2"
    local idx wifi disabled_val dhcp_ignore

    idx="${shop#shop}"
    wifi="shop${idx}_5g"

    if [ "$enable" = "1" ]; then
        disabled_val="0"
        dhcp_ignore="0"
    else
        disabled_val="1"
        dhcp_ignore="1"
    fi

    uci -q set network."$shop".disabled="$disabled_val"
    uci -q set dhcp."$shop".ignore="$dhcp_ignore"
    uci -q set wireless."$wifi".disabled="$disabled_val"
}

ensure_sqm_section() {
    local shop="$1"
    local sec="cb_${shop}"
    local sid

    uci -q get sqm."$sec" >/dev/null 2>&1 && {
        echo "$sec"
        return 0
    }

    sid="$(uci -q add sqm queue)" || return 1
    uci -q rename sqm."$sid"="$sec"
    echo "$sec"
    return 0
}

apply_sqm_limit() {
    local shop="$1"
    local up down sec enabled

    uci -q get sqm >/dev/null 2>&1 || return 0

    up="$(uci -q get cb-policy."$shop".up_kbit || echo 0)"
    down="$(uci -q get cb-policy."$shop".down_kbit || echo 0)"
    up="$(num_or_zero "$up")"
    down="$(num_or_zero "$down")"

    sec="$(ensure_sqm_section "$shop")" || return 0
    enabled="0"
    if [ "$up" -gt 0 ] && [ "$down" -gt 0 ]; then
        enabled="1"
    fi

    uci -q set sqm."$sec".interface="$shop"
    uci -q set sqm."$sec".download="$down"
    uci -q set sqm."$sec".upload="$up"
    uci -q set sqm."$sec".qdisc='cake'
    uci -q set sqm."$sec".script='piece_of_cake.qos'
    uci -q set sqm."$sec".linklayer='none'
    uci -q set sqm."$sec".enabled="$enabled"
    uci -q commit sqm

    if [ -x /etc/init.d/sqm ]; then
        /etc/init.d/sqm restart >/dev/null 2>&1
    fi
}

apply_whitelist() {
    local shop="$1"
    local idx wifi wl m

    idx="${shop#shop}"
    wifi="shop${idx}_5g"
    wl="$(uci -q get cb-policy."$shop".whitelist || true)"

    if [ -n "$wl" ]; then
        uci -q set wireless."$wifi".macfilter='allow'
        uci -q delete wireless."$wifi".maclist
        for m in $wl; do
            uci -q add_list wireless."$wifi".maclist="$m"
        done
    else
        uci -q delete wireless."$wifi".macfilter
        uci -q delete wireless."$wifi".maclist
    fi
}

apply_template() {
    local shop="$1"
    local tpl="$2"

    case "$shop" in
        shop1|shop2|shop3|shop4|shop5) ;;
        *)
            echo "invalid_shop"
            return 1
            ;;
    esac

    case "$tpl" in
        direct|proxy|blocked) ;;
        *)
            echo "invalid_template"
            return 1
            ;;
    esac

    uci -q set cb-policy."$shop".template="$tpl"
    uci -q set cb-policy."$shop".egress="$tpl"
    uci -q set cb-policy."$shop".current="$tpl"
    uci -q set cb-policy."$shop".sched_blocked='0'

    if [ "$tpl" = "blocked" ]; then
        apply_runtime_state "$shop" 0
    else
        apply_runtime_state "$shop" 1
    fi

    apply_whitelist "$shop"
    apply_sqm_limit "$shop"

    uci -q commit cb-policy
    uci -q commit network
    uci -q commit dhcp
    uci -q commit wireless
    /sbin/reload_config >/dev/null 2>&1
    wifi reload >/dev/null 2>&1

    /usr/bin/cb-eventlog write policy "apply template=${tpl} shop=${shop}"
    echo "ok"
    return 0
}

check_schedule() {
    local shop="$1"
    local sched tpl sched_blocked begin end

    sched="$(uci -q get cb-policy."$shop".schedule || echo always)"
    tpl="$(uci -q get cb-policy."$shop".template || echo direct)"
    sched_blocked="$(uci -q get cb-policy."$shop".sched_blocked || echo 0)"

    if [ "$sched" = "always" ]; then
        if [ "$sched_blocked" = "1" ]; then
            uci -q set cb-policy."$shop".sched_blocked='0'
            uci -q commit cb-policy
            apply_template "$shop" "$tpl" >/dev/null 2>&1
        fi
        return 0
    fi

    begin="$(echo "$sched" | cut -d'-' -f1)"
    end="$(echo "$sched" | cut -d'-' -f2)"
    [ -n "$begin" ] && [ -n "$end" ] || return 0

    if is_now_in_range "$begin" "$end"; then
        if [ "$sched_blocked" = "1" ]; then
            uci -q set cb-policy."$shop".sched_blocked='0'
            uci -q commit cb-policy
            apply_template "$shop" "$tpl" >/dev/null 2>&1
            /usr/bin/cb-eventlog write policy "schedule open for ${shop}, restore template=${tpl}"
        fi
    else
        if [ "$sched_blocked" != "1" ]; then
            apply_runtime_state "$shop" 0
            uci -q set cb-policy."$shop".current='blocked(schedule)'
            uci -q set cb-policy."$shop".sched_blocked='1'
            uci -q commit cb-policy
            uci -q commit network
            uci -q commit dhcp
            uci -q commit wireless
            /sbin/reload_config >/dev/null 2>&1
            wifi reload >/dev/null 2>&1
            /usr/bin/cb-eventlog write policy "schedule block applied to ${shop}"
        fi
    fi
}

build_status() {
    local items=""
    local i shop tpl cur egress schedule disabled up down wl sched_blocked
    local tpl_e cur_e egress_e schedule_e wl_e

    for i in 1 2 3 4 5; do
        shop="shop$i"
        tpl="$(uci -q get cb-policy.$shop.template || echo direct)"
        cur="$(uci -q get cb-policy.$shop.current || echo "$tpl")"
        egress="$(uci -q get cb-policy.$shop.egress || echo direct)"
        schedule="$(uci -q get cb-policy.$shop.schedule || echo always)"
        disabled="$(uci -q get network.$shop.disabled || echo 1)"
        up="$(uci -q get cb-policy.$shop.up_kbit || echo 0)"
        down="$(uci -q get cb-policy.$shop.down_kbit || echo 0)"
        wl="$(uci -q get cb-policy.$shop.whitelist || true)"
        sched_blocked="$(uci -q get cb-policy.$shop.sched_blocked || echo 0)"

        tpl_e="$(json_escape "$tpl")"
        cur_e="$(json_escape "$cur")"
        egress_e="$(json_escape "$egress")"
        schedule_e="$(json_escape "$schedule")"
        wl_e="$(json_escape "$wl")"

        [ -n "$items" ] && items="$items,"
        items="$items{\"shop\":\"$shop\",\"template\":\"$tpl_e\",\"current\":\"$cur_e\",\"egress\":\"$egress_e\",\"schedule\":\"$schedule_e\",\"disabled\":$disabled,\"up_kbit\":$up,\"down_kbit\":$down,\"whitelist\":\"$wl_e\",\"sched_blocked\":$sched_blocked}"
    done

    cat > "$STATUS_FILE" <<EOF
{"timestamp":"$(date '+%Y-%m-%d %H:%M:%S')","enabled":$ENABLED,"shops":[$items]}
EOF
}

run_once() {
    local i
    read_global_cfg
    [ "$ENABLED" = "1" ] || {
        echo '{"timestamp":"'"$(date '+%Y-%m-%d %H:%M:%S')"'","enabled":false}' > "$STATUS_FILE"
        return
    }

    for i in 1 2 3 4 5; do
        check_schedule "shop$i"
    done
    build_status
}

daemon_loop() {
    while true; do
        run_once
        read_global_cfg
        sleep "$INTERVAL"
    done
}

case "$1" in
    daemon)
        daemon_loop
        ;;
    apply_template)
        [ -n "$2" ] && [ -n "$3" ] || {
            echo "usage: $0 apply_template <shop1..shop5> <direct|proxy|blocked>"
            exit 1
        }
        apply_template "$2" "$3"
        ;;
    run_once|check)
        run_once
        ;;
    status)
        [ -f "$STATUS_FILE" ] && cat "$STATUS_FILE" || echo '{"enabled":false,"shops":[]}'
        ;;
    *)
        echo "usage: $0 {daemon|apply_template|run_once|status}"
        exit 1
        ;;
esac

exit 0
