#!/bin/sh

# helperFunctions.sh only exists on spruceOS; guard so this script also
# runs on stock OS where the file is absent.
if [ -f /mnt/SDCARD/spruce/scripts/helperFunctions.sh ]; then
    . /mnt/SDCARD/spruce/scripts/helperFunctions.sh
fi

# Disable idle/shutdown timer while file manager is open
killall -q idlemon 2>/dev/null
killall -q idlemon_mm.sh 2>/dev/null

export HOME="$(dirname "$0")"
cd "$HOME"

# Force vtree to re-auto-detect screen res every launch (config.ini is shared
# across devices but the saved dims would be stale if you swap cards between
# Brick/TSPS/Flip/etc.). Other settings (theme, keybinds) are preserved.
if [ -f "$HOME/config.ini" ]; then
    sed -i -e 's/^ScreenWidth=.*/ScreenWidth=0/' \
           -e 's/^ScreenHeight=.*/ScreenHeight=0/' \
           -e 's/^Rotation=.*/Rotation=0/' "$HOME/config.ini"

    # handle swapped X/Y on RGB30. Can this be handled more gracefully by editing a gamecontrollerdb.txt?
    if [ "$PLATFORM" = "RGB30" ]; then
        sed -i -e 's/^OskKeyBksp=x/OskKeyBksp=y/' \
               -e 's/^OskKeyShift=y/OskKeyShift=x/' \
               -e 's/^KeyMenu=y/KeyMenu=x/' "$HOME/config.ini"
    else
        sed -i -e 's/^OskKeyBksp=y/OskKeyBksp=x/' \
               -e 's/^OskKeyShift=x/OskKeyShift=y/' \
               -e 's/^KeyMenu=x/KeyMenu=y/' "$HOME/config.ini"
    fi
fi

# GLES window on the Mali blob. The Miniloong Pocket 1 has the same GLES-only
# Mali-G52 as the RGB30, so it needs the same context or vtree fails to open one.
{ [ "$PLATFORM" = "RGB30" ] || [ "$PLATFORM" = "Miniloong" ]; } && export VTREE_GLES=1

# Newer stock OS (Smart Pro S 2025+, kernel 5.15) does not export $PLATFORM,
# and future devices may report new names. Fall back to CPU architecture
# detection so the app still launches instead of exiting 1.
case "$PLATFORM" in
    "A30"|"Brick"|"BrickPro"|"Flip"|"Miniloong"|"SmartPro"|"SmartProS"|"Pixel2"|"RGB30"|"Zero"*|"MiyooMini"|"Anbernic"*)
        ;;
    *)
        case "$(uname -m 2>/dev/null)" in
            aarch64|arm64) PLATFORM="aarch64-fallback" ;;
        esac
        ;;
esac
# OTA tu dong (nen, im lang): kiem tra 30s sau khi mo app, roi moi 10 phut.
# Tat han bang FILEMANAGER_NO_OTA=1. Vong lap bi kill khi thoat app.
OTA_PID=""
if [ -x "$HOME/ota-update.sh" ]; then
    (
        sleep 30
        while :; do
            "$HOME/ota-update.sh" --apply >/dev/null 2>&1
            sleep 600
        done
    ) </dev/null >/dev/null 2>&1 &
    OTA_PID=$!
    # Kill vong lap nen + cac con (sleep/curl) khi script thoat theo bat
    # ky duong nao (ke ca exit 1 o nhanh unsupported platform).
    # Ly do tach FD khoi launcher: emulatorlauncher (Knulli/Batocera)
    # chay script voi stdout/stderr la PIPE va cho pipe EOF; tien trinh
    # mo coi giu pipe mo -> ES ket sau khi app thoat ("treo"). 2026-10-20
    trap '
      if [ -n "$OTA_PID" ]; then
        kill "$OTA_PID" 2>/dev/null
        for p in /proc/[0-9]*; do
          [ -r "$p/stat" ] || continue
          pp=$(awk "{print \$4}" "$p/stat" 2>/dev/null)
          [ "$pp" = "$OTA_PID" ] && kill "${p#/proc/}" 2>/dev/null
        done
      fi' EXIT
fi

case "$PLATFORM" in
    "A30")
        export LD_LIBRARY_PATH="$HOME/lib-A30:$LD_LIBRARY_PATH"
        killall -q -USR2 joystickinput
        ./vtree.a30 --rotate=3 >"$HOME/log.txt" 2>&1
        sync
        killall -q -USR2 joystickinput
        ;;
    "Brick"|"BrickPro"|"Flip"|"Miniloong"|"SmartPro"|"SmartProS"|"Pixel2"|"RGB30"|"Zero"*|"aarch64-fallback")
        ./vtree.aarch64 >"$HOME/log.txt" 2>&1
        sync
        ;;
    "MiyooMini")
        # freemma releases the display from PyUI before vtree takes over.
        export PATH="/mnt/SDCARD/spruce/miyoomini/bin:$PATH"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/miyoomini/lib:$LD_LIBRARY_PATH"
        export SDL_VIDEODRIVER=mmiyoo
        export SDL_AUDIODRIVER=mmiyoo
        export EGL_VIDEODRIVER=mmiyoo
        export SDL_MMIYOO_DOUBLE_BUFFER=1
        freemma
        ./vtree.mini >"$HOME/log.txt" 2>&1
        sync
        ;;
    "Anbernic"*)
        export_sdl_gamecontroller_map positional
        ./vtree.aarch64 >"$HOME/log.txt" 2>&1
        sync
        ;;
    *)
        log_message "File Management: unsupported PLATFORM: $PLATFORM"
        exit 1
        ;;
esac
