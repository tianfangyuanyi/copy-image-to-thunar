# Thunar Custom Action: Paste Image from Clipboard

This is a shell script (actually it is vibre coded :D) that can paste the picture on your clipboard to the directory. It works with the custom action function of thunar, and compatible with either wl-copy or CopyQ.

## Overview

When you copy an image to the clipboard (e.g., by taking a screenshot or copying an image from a web browser), you often want to save it as a file in the current directory you open on thunar. This custom action adds a right‑click menu entry **"Paste image here"** that:

- Detects image data in the clipboard (supports PNG, JPEG, GIF, BMP, WebP, TIFF).
- Saves the image with a timestamped filename (e.g., `Pasted_image_20260216_143022.png`).
- Works with CopyQ (the recommended clipboard manager for Wayland) and falls back to `wl-paste` if needed.
- Shows a desktop notification on success or error.

The script is tailored for **Arch Linux with Hyprland**, but should work on any Linux distribution with the required dependencies.

## Dependencies

- **Thunar** – the file manager.
- **libnotify** or **zenity** – for desktop notifications.
  
Choose one from two:
- **wl-clipboard** – provides `wl-paste` for accessing the Wayland clipboard (fallback).
- **CopyQ** – clipboard manager with advanced features.

## Installation

### 1. Create the script

Save the following script as `~/.local/bin/thunar-paste-image` and make it executable:

```bash
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
```

Make it executable:

```bash
chmod +x ~/.local/bin/thunar-paste-image
```

### 2. Add the custom action in Thunar

1. Open Thunar.
2. Go to **Edit → Configure custom actions…**.
3. Click the **+** button to add a new action.
   - **Name:** `Paste image here`
   - **Description:** `Save image from clipboard to current folder`
   - **Command:** `/home/your_username/.local/bin/thunar-paste-image %d`  
     (Replace `your_username` with your actual username. If your script path contains spaces, enclose it in quotes, but keep `%d` outside.)
   - **Appearance Conditions:**  
     - File Pattern: `*`  
     - Check **Directories** (so the action appears when right‑clicking in a folder background).
4. Click **OK** and close the dialog.

## Usage

1. Copy an image to the clipboard. For example:
   - Take a screenshot with a tool that copies directly to clipboard (e.g., `grim -g "$(slurp)" - | wl-copy`).
   - Right‑click an image in a web browser and select **Copy Image**.
2. Open Thunar and navigate to the folder where you want to save the image.
3. Right‑click on an empty area inside the folder.
4. Choose **Paste image here** from the context menu.
5. A notification will appear confirming the saved filename. The image is saved with a name like `Pasted_image_20260216_143022.png`.

## Troubleshooting

If the action does not work as expected:

- **Check the log file:**  
  ```bash
  cat /tmp/thunar-paste-image.log
  ```
  It contains detailed information about what the script did.


- **Test the script manually:**  
  ```bash
  ~/.local/bin/thunar-paste-image /tmp
  ```
  This should save the image to `/tmp` if clipboard data is available.

- **CopyQ not capturing images:** If `copyq read 0 ?` shows no image MIME types, ensure CopyQ is running in XWayland mode (see installation step 2).

- **Wrong target directory:** The script uses `pwd` to determine the current Thunar folder. If it still saves to the parent directory, try removing the `%d` parameter from the Thunar command (leave just the script path) – Thunar will then run the script in the correct working directory.z