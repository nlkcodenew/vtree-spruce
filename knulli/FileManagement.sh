#!/bin/bash
# FileManagement.sh — launcher cho muc Tools tren Knulli (Brick Pro).
# App payload: /userdata/system/filemanagement (vTree/FileManagement v1.4.5,
# ban build cho stock OS — chay nguyen ven tren Knulli: du SDL2/SDL2_ttf/
# SDL2_image; bin/7zz static cho tinh nang Extract).
APP=/userdata/system/filemanagement
export HOME="$APP"
cd "$APP" || exit 1

# config.ini dung /mnt/SDCARD lam thu muc mo dau cho 2 panel.
# Symlink nay da co san nho custom.sh; tao lai neu thieu.
[ -e /mnt/SDCARD ] || { mkdir -p /mnt 2>/dev/null; ln -sfn /userdata /mnt/SDCARD 2>/dev/null; }

# OTA tu dong, im lang — giu nguyen hanh vi ban stock OS.
# Tat han: FILEMANAGER_NO_OTA=1 (khai trong custom.sh neu muon).
# QUAN TRONG (fix treo khi thoat app tren Knulli): emulatorlauncher chay
# script nay voi stdout/stderr la PIPE va communicate() cho pipe EOF.
# Vong nen PHAI redirect ca 3 FD ra khoi pipe cha, neu khong tien trinh
# sleep/curl mo coi giu pipe mo -> ES ket sau khi app thoat ("treo").
OTA_PID=""
if [ -z "$FILEMANAGER_NO_OTA" ] && [ -x "$APP/ota-update.sh" ]; then
  (
    sleep 30
    while :; do
      "$APP/ota-update.sh" --apply >>"$APP/ota.log" 2>&1
      sleep 600
    done
  ) </dev/null >>"$APP/ota.log" 2>&1 &
  OTA_PID=$!
fi

./vtree.aarch64 >"$APP/log.txt" 2>&1
CODE=$?

# Don vong OTA: kill subshell + cac con truc tiep (sleep/curl).
# Knulli khong co pkill -> quet /proc theo PPID.
if [ -n "$OTA_PID" ]; then
  kill "$OTA_PID" 2>/dev/null
  for p in /proc/[0-9]*; do
    [ -r "$p/stat" ] || continue
    pp=$(awk '{print $4}' "$p/stat" 2>/dev/null)
    [ "$pp" = "$OTA_PID" ] && kill "${p#/proc/}" 2>/dev/null
  done
fi
sync
exit "$CODE"
