#!/bin/sh

CHECK_FILE="/tmp/cb-upgrade-check.json"
BACKUP_FILE="/tmp/cb-upgrade-backup.tar.gz"

json_bool() {
    [ "$1" = "1" ] && echo true || echo false
}

detect_rollback_capability() {
    local slots
    slots="$(grep -Ec '"(firmware2|kernel2|rootfs2)"' /proc/mtd 2>/dev/null || true)"
    if [ "$slots" -gt 0 ]; then
        echo "1"
    else
        echo "0"
    fi
}

do_check() {
    local image="$1"
    local expected_sha="$2"
    local board image_ok=0 sha_ok=0 compat_ok=0 space_ok=0 partition_ok=0 model_ok=0
    local rollback_ready=0 all_ok=0
    local note="" compat_note="" rollback_note=""
    local size available need actual_sha expected_sha_lc actual_sha_lc
    local compat_out

    if [ -f "$image" ]; then
        image_ok=1
        size="$(wc -c < "$image" 2>/dev/null || echo 0)"
        if [ "$size" -lt 4194304 ]; then
            image_ok=0
            note="image_too_small"
        fi
    else
        size=0
        note="image_not_found"
    fi

    if [ "$image_ok" = "1" ] && [ -n "$expected_sha" ]; then
        actual_sha="$(sha256sum "$image" | awk '{print $1}')"
        expected_sha_lc="$(echo "$expected_sha" | tr 'A-Z' 'a-z')"
        actual_sha_lc="$(echo "$actual_sha" | tr 'A-Z' 'a-z')"
        if [ "$actual_sha_lc" = "$expected_sha_lc" ]; then
            sha_ok=1
        else
            note="sha_mismatch"
        fi
    else
        sha_ok=1
    fi

    if [ "$image_ok" = "1" ]; then
        compat_out="$(/sbin/sysupgrade -T "$image" 2>&1)"
        if [ "$?" = "0" ]; then
            compat_ok=1
            model_ok=1
            compat_note="ok"
        else
            compat_note="$(echo "$compat_out" | tail -n 1 | sed 's/"/\\"/g')"
            [ -z "$note" ] && note="sysupgrade_test_failed"
        fi
    fi

    available="$(df -k /tmp | awk 'NR==2{print $4}')"
    need=$(( (size / 1024) + 16384 ))
    if [ "$available" -gt "$need" ]; then
        space_ok=1
    else
        [ -z "$note" ] && note="insufficient_tmp_space"
    fi

    if grep -Eq '"(ubi|firmware|kernel|rootfs)"' /proc/mtd 2>/dev/null; then
        partition_ok=1
    else
        [ -z "$note" ] && note="partition_layout_unknown"
    fi

    rollback_ready="$(detect_rollback_capability)"
    if [ "$rollback_ready" = "1" ]; then
        rollback_note="dual_slot_detected"
    else
        rollback_note="single_slot_only_config_backup_fallback"
    fi

    board="$(ubus call system board | jsonfilter -e '@.board_name' 2>/dev/null)"
    [ -z "$board" ] && board="unknown"

    if [ "$image_ok" = "1" ] && [ "$sha_ok" = "1" ] && [ "$compat_ok" = "1" ] && [ "$space_ok" = "1" ] && [ "$partition_ok" = "1" ] && [ "$model_ok" = "1" ]; then
        all_ok=1
        [ -z "$note" ] && note="ok"
    fi

    cat > "$CHECK_FILE" <<EOF
{
  "timestamp":"$(date '+%Y-%m-%d %H:%M:%S')",
  "image":"$image",
  "board":"$board",
  "image_exists":$(json_bool "$image_ok"),
  "sha_ok":$(json_bool "$sha_ok"),
  "compat_ok":$(json_bool "$compat_ok"),
  "model_ok":$(json_bool "$model_ok"),
  "space_ok":$(json_bool "$space_ok"),
  "partition_ok":$(json_bool "$partition_ok"),
  "rollback_ready":$(json_bool "$rollback_ready"),
  "rollback_note":"$rollback_note",
  "compat_note":"$compat_note",
  "all_ok":$(json_bool "$all_ok"),
  "note":"$note"
}
EOF
    cat "$CHECK_FILE"
    [ "$all_ok" = "1" ]
}

do_upgrade() {
    local image="$1"
    local expected_sha="$2"
    local rollback_ready

    do_check "$image" "$expected_sha" || return 1
    rollback_ready="$(jsonfilter -i "$CHECK_FILE" -e '@.rollback_ready' 2>/dev/null)"

    /sbin/sysupgrade -b "$BACKUP_FILE" >/dev/null 2>&1 || true
    if [ "$rollback_ready" = "true" ]; then
        /usr/bin/cb-eventlog write upgrade "safe upgrade started (dual-slot): $image"
    else
        /usr/bin/cb-eventlog write upgrade "safe upgrade started (single-slot fallback): $image"
    fi

    if ! /sbin/sysupgrade "$image"; then
        /usr/bin/cb-eventlog write upgrade "sysupgrade failed, try config restore"
        [ -f "$BACKUP_FILE" ] && /sbin/sysupgrade -r "$BACKUP_FILE" >/dev/null 2>&1 || true
        return 1
    fi
    return 0
}

case "$1" in
    check)
        do_check "$2" "$3"
        ;;
    upgrade)
        do_upgrade "$2" "$3"
        ;;
    *)
        echo "usage: $0 {check <image> [sha256]|upgrade <image> [sha256]}"
        exit 1
        ;;
esac

exit $?
