#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$REPO_ROOT/.work"
OVERLAY_DIR="$WORK_DIR/openwrtai-overlay"
ARCHIVE_PATH="$WORK_DIR/cbshield-openwrtai-overlay.tgz"
MANIFEST_PATH="$WORK_DIR/openwrtai-overlay.manifest"

copy_file() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

copy_tree() {
    local src="$1"
    local dst="$2"

    mkdir -p "$dst"
    cp -R "$src"/. "$dst"/
}

copy_repo_files() {
    local src_root="$REPO_ROOT/files"
    local src
    local rel

    if [ ! -d "$src_root" ]; then
        return
    fi

    while IFS= read -r -d '' src; do
        rel="${src#$src_root/}"
        copy_file "$src" "$OVERLAY_DIR/$rel"
    done < <(find "$src_root" -type f -print0 | sort -z)
}

copy_package_files() {
    local base="$REPO_ROOT/packages/cb-riskcontrol/files"

    copy_file "$base/cb-riskcontrol.sh" "$OVERLAY_DIR/usr/bin/cb-riskcontrol"
    copy_file "$base/cb-riskcontrol.init" "$OVERLAY_DIR/etc/init.d/cb-riskcontrol"
    copy_file "$base/cb-riskcontrol.conf" "$OVERLAY_DIR/etc/config/cb-riskcontrol"

    copy_file "$base/cb-healthcheck.sh" "$OVERLAY_DIR/usr/bin/cb-healthcheck"
    copy_file "$base/cb-healthcheck.init" "$OVERLAY_DIR/etc/init.d/cb-healthcheck"
    copy_file "$base/cb-health.conf" "$OVERLAY_DIR/etc/config/cb-health"

    copy_file "$base/cb-ha-monitor.sh" "$OVERLAY_DIR/usr/bin/cb-ha-monitor"
    copy_file "$base/cb-ha-monitor.init" "$OVERLAY_DIR/etc/init.d/cb-ha-monitor"
    copy_file "$base/cb-ha.conf" "$OVERLAY_DIR/etc/config/cb-ha"

    copy_file "$base/cb-dns-guard.sh" "$OVERLAY_DIR/usr/bin/cb-dns-guard"
    copy_file "$base/cb-dns-guard.init" "$OVERLAY_DIR/etc/init.d/cb-dns-guard"
    copy_file "$base/cb-dns-guard.conf" "$OVERLAY_DIR/etc/config/cb-dns-guard"

    copy_file "$base/cb-eventlog.sh" "$OVERLAY_DIR/usr/bin/cb-eventlog"
    copy_file "$base/cb-safe-upgrade.sh" "$OVERLAY_DIR/usr/bin/cb-safe-upgrade"
    copy_file "$base/cb-wizard.sh" "$OVERLAY_DIR/usr/bin/cb-wizard"
    copy_file "$base/cb-wizard.conf" "$OVERLAY_DIR/etc/config/cb-wizard"

    copy_file "$base/cb-portal.init" "$OVERLAY_DIR/etc/init.d/cb-portal"
    copy_file "$base/cb-portal.conf" "$OVERLAY_DIR/etc/config/cb-portal"
    copy_file "$base/cb-portal.html" "$OVERLAY_DIR/www/cb-portal/index.html"
}

copy_luci_files() {
    local base="$REPO_ROOT/luci-theme-cbshield"

    copy_tree \
        "$base/luasrc/controller/cbshield" \
        "$OVERLAY_DIR/usr/lib/lua/luci/controller/cbshield"
    copy_tree \
        "$base/luasrc/view/cbshield" \
        "$OVERLAY_DIR/usr/lib/lua/luci/view/cbshield"
    copy_tree \
        "$base/htdocs/luci-static/cbshield" \
        "$OVERLAY_DIR/www/luci-static/cbshield"

    if [ -d "$base/root" ]; then
        copy_tree "$base/root" "$OVERLAY_DIR"
    fi
}

write_manifest() {
    (
        cd "$OVERLAY_DIR"
        find . -type f | LC_ALL=C sort | sed 's#^\./##'
    ) > "$MANIFEST_PATH"
}

main() {
    rm -rf "$OVERLAY_DIR"
    mkdir -p "$OVERLAY_DIR" "$WORK_DIR"

    copy_repo_files
    copy_package_files
    copy_luci_files

    chmod +x "$OVERLAY_DIR"/usr/bin/* 2>/dev/null || true
    chmod +x "$OVERLAY_DIR"/etc/init.d/* 2>/dev/null || true
    chmod +x "$OVERLAY_DIR"/etc/uci-defaults/* 2>/dev/null || true

    write_manifest

    rm -f "$ARCHIVE_PATH"
    tar -czf "$ARCHIVE_PATH" -C "$OVERLAY_DIR" .

    echo "overlay_dir=$OVERLAY_DIR"
    echo "archive_path=$ARCHIVE_PATH"
    echo "manifest_path=$MANIFEST_PATH"
}

main "$@"
