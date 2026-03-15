#!/bin/bash
# Paste image from clipboard into the current Thunar directory

set -euo pipefail

PREFIX="Pasted_image"
LOG_FILE="/tmp/thunar-paste-image.log"

# Logging
> "$LOG_FILE"
log() { echo "$(date): $*" >> "$LOG_FILE"; }
error_exit() {
    log "Error: $*"
    if command -v notify-send &>/dev/null; then
        notify-send -u critical "Error" "$*"
    elif command -v zenity &>/dev/null; then
        zenity --error --text="$*"
    fi
    exit 1
}

# Determine target directory: use pwd (Thunar's current dir) or fallback to argument
if [ -n "${1:-}" ] && [ -d "$1" ]; then
    TARGET_DIR=$(realpath "$1")
    log "Using argument directory: $TARGET_DIR"
else
    TARGET_DIR=$(pwd)
    log "Using current working directory: $TARGET_DIR"
fi

mkdir -p "$TARGET_DIR" || error_exit "Cannot create directory $TARGET_DIR"

# ---------- CopyQ backend (reads from internal storage) ----------
save_from_copyq() {
    command -v copyq &>/dev/null || return 1

    local item_count=$(copyq count 2>>"$LOG_FILE" || echo 0)
    log "copyq count: $item_count"
    [ "$item_count" -eq 0 ] && return 1

    local mimes=$(copyq read 0 ? 2>>"$LOG_FILE")
    log "raw mimes: $mimes"
    local image_mimes=$(echo "$mimes" | grep "^image/" || true)
    log "image mimes: $image_mimes"
    [ -z "$image_mimes" ] && return 1

    local mime=$(echo "$image_mimes" | head -1)
    local ext="${mime#image/}"
    [ "$ext" = "jpeg" ] && ext="jpg"

    local filename="${PREFIX}_$(date +%Y%m%d_%H%M%S).$ext"
    local filepath="$TARGET_DIR/$filename"
    log "Trying CopyQ: $mime -> $filepath"

    if copyq read 0 "$mime" > "$filepath" 2>>"$LOG_FILE"; then
        if [ -s "$filepath" ]; then
            local size=$(stat -c %s "$filepath")
            log "CopyQ success, size: $size bytes"
            echo "$filepath"
            return 0
        else
            log "CopyQ saved empty file"
            rm -f "$filepath"
            return 1
        fi
    else
        log "copyq read command failed"
        return 1
    fi
}

# ---------- wl-paste backend (Wayland native) ----------
save_from_wlpaste() {
    command -v wl-paste &>/dev/null || return 1
    local types=$(wl-paste --list-types 2>/dev/null | grep "^image/" || true)
    [ -z "$types" ] && return 1
    local mime=$(echo "$types" | head -1)
    local ext="${mime#image/}"
    [ "$ext" = "jpeg" ] && ext="jpg"
    local filename="${PREFIX}_$(date +%Y%m%d_%H%M%S).$ext"
    local filepath="$TARGET_DIR/$filename"
    log "Trying wl-paste: $mime -> $filepath"
    if wl-paste --type "$mime" > "$filepath" 2>>"$LOG_FILE" && [ -s "$filepath" ]; then
        log "wl-paste success"
        echo "$filepath"
        return 0
    else
        log "wl-paste failed"
        return 1
    fi
}

# ---------- Main ----------
saved_file=""
# Try CopyQ first (since you're using it)
if save_from_copyq; then
    saved_file=$(save_from_copyq)   # Note: called twice, but works
elif save_from_wlpaste; then
    saved_file=$(save_from_wlpaste)
fi

if [ -n "$saved_file" ]; then
    filename=$(basename "$saved_file")
    if command -v notify-send &>/dev/null; then
        notify-send "Image pasted" "Saved as $filename"
    fi
    log "Final success: $saved_file"
else
    error_exit "No image data found in clipboard (CopyQ or wl-paste)"
fi
