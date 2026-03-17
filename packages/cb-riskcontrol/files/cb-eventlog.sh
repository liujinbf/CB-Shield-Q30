#!/bin/sh

LOG_FILE="/tmp/cb-events.log"
MAX_LINES=800

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_event() {
    local type="$1"
    shift
    local msg="$*"
    local ts
    local host

    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    host="$(uci -q get system.@system[0].hostname)"

    printf '{"timestamp":"%s","type":"%s","host":"%s","message":"%s"}\n' \
        "$(escape_json "$ts")" \
        "$(escape_json "$type")" \
        "$(escape_json "$host")" \
        "$(escape_json "$msg")" >> "$LOG_FILE"

    tail -n "$MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    logger -t cb-event "$type: $msg"
}

case "$1" in
    write)
        shift
        [ -n "$1" ] || {
            echo "usage: $0 write <type> <message>"
            exit 1
        }
        type="$1"
        shift
        write_event "$type" "$*"
        ;;
    dump)
        [ -f "$LOG_FILE" ] && cat "$LOG_FILE" || true
        ;;
    clear)
        : > "$LOG_FILE"
        ;;
    *)
        echo "usage: $0 {write <type> <message>|dump|clear}"
        exit 1
        ;;
esac

exit 0
