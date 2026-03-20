#!/bin/sh
set -eu

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DEFAULT_BUNDLE="$SELF_DIR/cbshield-kwrt-runtime.tgz"
TMP_BUNDLE="/tmp/cbshield-kwrt-runtime.tgz"
BACKUP_DIR="/etc/cbshield/runtime-backup-$(date +%Y%m%d-%H%M%S)"
RESTART_LOG="/tmp/cbshield-runtime-restart.log"

log() {
    echo ">>> $*"
}

warn() {
    echo "!!! $*" >&2
}

fatal() {
    echo "xxx $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
??:
  sh cbshield-kwrt-install.sh [bundle_path]

???????:
  1. ????????? cbshield-kwrt-runtime.tgz
  2. /tmp/cbshield-kwrt-runtime.tgz
EOF
}

resolve_bundle() {
    if [ "$#" -gt 0 ] && [ -n "$1" ]; then
        echo "$1"
        return 0
    fi

    if [ -f "$DEFAULT_BUNDLE" ]; then
        echo "$DEFAULT_BUNDLE"
        return 0
    fi

    if [ -f "$TMP_BUNDLE" ]; then
        echo "$TMP_BUNDLE"
        return 0
    fi

    return 1
}

require_root() {
    [ "$(id -u)" = "0" ] || fatal "??? root ??????"
}

ensure_base_tools() {
    for cmd in tar uci opkg ubus; do
        command -v "$cmd" >/dev/null 2>&1 || fatal "??????: $cmd"
    done
}

install_missing_packages() {
    local missing=""

    command -v curl >/dev/null 2>&1 || missing="$missing curl"
    command -v jsonfilter >/dev/null 2>&1 || missing="$missing jsonfilter"
    command -v nft >/dev/null 2>&1 || missing="$missing nftables-json"
    [ -x /usr/sbin/uhttpd ] || missing="$missing uhttpd"
    [ -d /usr/lib/lua/luci ] || missing="$missing luci"
    [ -f /usr/lib/lua/luci/dispatcher.lua ] || missing="$missing luci-base"
    [ -f /usr/lib/lua/luci/model/cbi.lua ] || missing="$missing luci-compat"

    if [ -z "$missing" ]; then
        return 0
    fi

    log "?????????,????:$missing"
    opkg update
    # shellcheck disable=SC2086
    opkg install $missing
}

backup_existing_files() {
    local bundle="$1"
    local rel
    local target

    mkdir -p "$BACKUP_DIR"
    while IFS= read -r rel; do
        rel="${rel#./}"
        [ -n "$rel" ] || continue
        case "$rel" in
            */)
                continue
                ;;
        esac
        target="/$rel"
        if [ -f "$target" ] || [ -L "$target" ]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
            cp -a "$target" "$BACKUP_DIR/$rel"
        fi
    done <<EOF
$(tar -tzf "$bundle")
EOF
}

extract_bundle() {
    local bundle="$1"
    tar -xzf "$bundle" -C /
}

fix_permissions() {
    chmod +x /usr/bin/cb-riskcontrol 2>/dev/null || true
    chmod +x /usr/bin/cb-eventlog 2>/dev/null || true
    chmod +x /usr/bin/cb-healthcheck 2>/dev/null || true
    chmod +x /usr/bin/cb-ha-monitor 2>/dev/null || true
    chmod +x /usr/bin/cb-dns-guard 2>/dev/null || true
    chmod +x /usr/bin/cb-safe-upgrade 2>/dev/null || true
    chmod +x /usr/bin/cb-wizard 2>/dev/null || true
    chmod +x /usr/bin/cb-openclash-setup 2>/dev/null || true

    for svc in cb-riskcontrol cb-portal cb-healthcheck cb-ha-monitor cb-dns-guard; do
        chmod +x "/etc/init.d/$svc" 2>/dev/null || true
    done
}

apply_defaults() {
    local defaults

    for defaults in /etc/uci-defaults/80_cbshield-theme /etc/uci-defaults/90_v3_optimizations; do
        [ -f "$defaults" ] || continue
        log "?? defaults: $defaults"
        sh "$defaults"
        rm -f "$defaults"
    done
}

clear_luci_cache() {
    rm -f /tmp/luci-indexcache 2>/dev/null || true
    rm -rf /tmp/luci-modulecache 2>/dev/null || true
    rm -rf /tmp/luci-*cache 2>/dev/null || true
}

restart_services_async() {
    cat > /tmp/cbshield-runtime-restart.sh <<'EOF'
#!/bin/sh
sleep 2
/etc/init.d/network restart > /tmp/cbshield-runtime-restart.log 2>&1 || true
wifi reload >> /tmp/cbshield-runtime-restart.log 2>&1 || true
/etc/init.d/rpcd restart >> /tmp/cbshield-runtime-restart.log 2>&1 || true
/etc/init.d/uhttpd restart >> /tmp/cbshield-runtime-restart.log 2>&1 || true
EOF
    chmod +x /tmp/cbshield-runtime-restart.sh
    /tmp/cbshield-runtime-restart.sh >/dev/null 2>&1 &
}

show_summary() {
    local board_name
    board_name="$(ubus call system board 2>/dev/null | jsonfilter -e '@.board_name' 2>/dev/null || echo 'unknown')"

    log "????,????: $board_name"
    log "????????: $BACKUP_DIR"
    log "??? LuCI ??????,?? 5-10 ????"
    log "??????????: http://192.168.10.1/"
    log "????????: CB-Shield-Office / CB-Shield-Office-5G"
    log "??????????: $RESTART_LOG"
}

main() {
    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
    esac

    require_root
    ensure_base_tools

    BUNDLE_PATH="$(resolve_bundle "${1:-}")" || fatal "??? runtime bundle,?? cbshield-kwrt-runtime.tgz ??? /tmp ????????????"
    [ -f "$BUNDLE_PATH" ] || fatal "bundle ???: $BUNDLE_PATH"

    log "??????? Kwrt ????? CB-Shield ???"
    install_missing_packages
    backup_existing_files "$BUNDLE_PATH"
    extract_bundle "$BUNDLE_PATH"
    fix_permissions
    apply_defaults
    clear_luci_cache
    restart_services_async
    show_summary
}

main "$@"
