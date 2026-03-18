#!/bin/sh

STATUS_FILE="/tmp/cb-openclash-setup.json"

trim() {
    echo "${1:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

json_escape() {
    printf '%s' "${1:-}" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\r/\\r/g;s/\n/\\n/g'
}

json_bool() {
    [ "${1:-0}" = "1" ] && echo true || echo false
}

service_exists() {
    [ -x "/etc/init.d/$1" ]
}

service_running() {
    service_exists "$1" || return 1
    /etc/init.d/"$1" status >/dev/null 2>&1
}

valid_http_url() {
    case "${1:-}" in
        http://*|https://*) return 0 ;;
        *) return 1 ;;
    esac
}

sanitize_profile() {
    local value
    value="$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9._-]/_/g;s/__*/_/g;s/^[_ .-]*//;s/[_ .-]*$//')"
    [ -n "$value" ] || value="cbshield"
    printf '%s' "$value"
}

find_subscribe_section() {
    local target="$1"
    local section current

    while IFS= read -r section; do
        current="$(uci -q get "openclash.$section.name")"
        [ "$current" = "$target" ] && {
            echo "$section"
            return 0
        }
    done <<EOF
$(uci show openclash 2>/dev/null | sed -n 's/^openclash\.\([^=]*\)=config_subscribe$/\1/p')
EOF
    return 1
}

save_wizard_state() {
    local enabled="$1"
    local proxy_type="$2"
    local subscription="$3"
    local profile="$4"
    local mode="$5"
    local operation="$6"

    uci -q set cb-wizard.main.proxy_enabled="$enabled"
    uci -q set cb-wizard.main.proxy_type="$proxy_type"
    uci -q set cb-wizard.main.openclash_subscription="$subscription"
    uci -q set cb-wizard.main.openclash_profile="$profile"
    uci -q set cb-wizard.main.openclash_mode="$mode"
    uci -q set cb-wizard.main.openclash_operation_mode="$operation"
    uci commit cb-wizard
}

disable_openclash() {
    service_exists openclash || return 0
    uci -q set openclash.config.enable='0'
    uci commit openclash
    /etc/init.d/openclash disable >/dev/null 2>&1 || true
    /etc/init.d/openclash stop >/dev/null 2>&1 || true
}

write_status() {
    local installed enabled running config_path subscription profile mode operation

    installed=0
    service_exists openclash && installed=1

    enabled=0
    [ "$(uci -q get cb-wizard.main.proxy_enabled)" = "1" ] && enabled=1

    running=0
    service_running openclash && running=1

    config_path="$(trim "$(uci -q get openclash.config.config_path)")"
    subscription="$(trim "$(uci -q get cb-wizard.main.openclash_subscription)")"
    profile="$(trim "$(uci -q get cb-wizard.main.openclash_profile)")"
    mode="$(trim "$(uci -q get cb-wizard.main.openclash_mode)")"
    operation="$(trim "$(uci -q get cb-wizard.main.openclash_operation_mode)")"

    cat > "$STATUS_FILE" <<EOF
{
  "installed":$(json_bool "$installed"),
  "enabled":$(json_bool "$enabled"),
  "running":$(json_bool "$running"),
  "config_ready":$([ -n "$config_path" ] && echo true || echo false),
  "profile":"$(json_escape "$profile")",
  "mode":"$(json_escape "${mode:-rule}")",
  "operation_mode":"$(json_escape "${operation:-fake-ip}")",
  "subscription":"$(json_escape "$subscription")"
}
EOF
    cat "$STATUS_FILE"
}

apply_openclash() {
    local enabled="$1"
    local proxy_type="$2"
    local subscription="$3"
    local profile="$4"
    local mode="$5"
    local operation="$6"
    local section generated_yaml generated_yml running message

    [ "$proxy_type" = "openclash" ] || {
        echo '{"status":"error","message":"unsupported_proxy_type"}'
        return 1
    }

    profile="$(sanitize_profile "$profile")"
    [ -n "$mode" ] || mode="rule"
    [ -n "$operation" ] || operation="fake-ip"

    case "$mode" in
        rule|global|direct|script) ;;
        *) mode="rule" ;;
    esac

    case "$operation" in
        fake-ip|redir-host) ;;
        *) operation="fake-ip" ;;
    esac

    save_wizard_state "$enabled" "$proxy_type" "$subscription" "$profile" "$mode" "$operation"

    if [ "$enabled" != "1" ]; then
        disable_openclash
        echo '{"status":"ok","message":"openclash_disabled","running":false}'
        return 0
    fi

    service_exists openclash || {
        echo '{"status":"error","message":"openclash_not_installed"}'
        return 1
    }

    valid_http_url "$subscription" || {
        echo '{"status":"error","message":"openclash_subscription_invalid"}'
        return 1
    }

    mkdir -p /etc/openclash/config

    section="$(find_subscribe_section "$profile" || true)"
    [ -n "$section" ] || section="$(uci add openclash config_subscribe)"

    uci -q set openclash.config.enable='1'
    uci -q set openclash.config.proxy_mode="$mode"
    uci -q set openclash.config.operation_mode="$operation"
    uci -q set openclash.config.en_mode="$operation"
    uci -q set openclash.config.router_self_proxy='1'
    uci -q set openclash.config.enable_udp_proxy='1'
    uci -q set openclash.config.disable_udp_quic='1'
    uci -q set "openclash.$section.name=$profile"
    uci -q set "openclash.$section.address=$subscription"
    uci -q set "openclash.$section.sub_ua=clash.meta"
    uci -q set "openclash.$section.sub_convert=0"
    uci -q set "openclash.$section.emoji=false"
    uci -q set "openclash.$section.udp=true"
    uci -q set "openclash.$section.skip_cert_verify=false"
    uci -q set "openclash.$section.sort=false"
    uci -q set "openclash.$section.node_type=false"
    uci -q set "openclash.$section.rule_provider=false"
    uci -q delete "openclash.$section.convert_address"
    uci -q delete "openclash.$section.template"
    uci -q delete "openclash.$section.custom_params"
    uci -q delete "openclash.$section.keyword"
    uci -q delete "openclash.$section.ex_keyword"
    uci -q delete "openclash.$section.de_ex_keyword"
    uci commit openclash

    /usr/share/openclash/openclash.sh "$profile" >/tmp/cb-openclash-import.log 2>&1 || {
        echo '{"status":"error","message":"openclash_subscription_import_failed"}'
        return 1
    }

    generated_yaml="/etc/openclash/config/$profile.yaml"
    generated_yml="/etc/openclash/config/$profile.yml"
    if [ -f "$generated_yaml" ]; then
        uci -q set openclash.config.config_path="$generated_yaml"
    elif [ -f "$generated_yml" ]; then
        uci -q set openclash.config.config_path="$generated_yml"
    fi
    uci commit openclash

    /etc/init.d/openclash enable >/dev/null 2>&1 || true
    /etc/init.d/openclash restart >/dev/null 2>&1 || true

    running=false
    message="openclash_imported"
    if service_running openclash; then
        running=true
        message="openclash_ready"
    fi

    /usr/bin/cb-eventlog write wizard "openclash setup applied" >/dev/null 2>&1 || true
    printf '{"status":"ok","message":"%s","profile":"%s","running":%s}\n' \
        "$message" "$(json_escape "$profile")" "$running"
    return 0
}

case "$1" in
    status)
        write_status
        ;;
    apply)
        shift
        apply_openclash "$@"
        ;;
    *)
        echo "usage: $0 {status|apply <enabled> <proxy_type> <subscription> <profile> <mode> <operation_mode>}"
        exit 1
        ;;
esac

exit 0
