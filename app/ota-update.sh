#!/bin/sh
# ota-update.sh — OTA tu dong, IM LANG cho FileManagement (vTree).
# Hoc tu Trimui-LocalSend (files/ota-update.sh):
#   - Tai manifest qua TLS (raw.githubusercontent / jsdelivr fallback)
#   - Binary verify chu ky Ed25519 cua manifest TRUOC KHI tin bat ky
#     hash/path/URL nao (--verify-manifest, dung code TweetNaCl nhung san;
#     may khong co python3/openssl CLI nen khong verify bang shell duoc)
#   - Verify sha256 file zip truoc khi giai nen
#   - KHONG bao gio dung toi du lieu nguoi dung: config.ini, *.log,
#     cac file user tu them trong fonts/ va lang/ (chi chep de file nao
#     co trong zip)
#   - Ghi de atomic tung file (.ota-new -> rename); chmod +x cho *.sh va bin/*
#
# Ve viec ghi de len thu muc app DANG CHAY:
#   Script nay chay nen tu launch.sh trong khi vtree.aarch64 dang chay.
#   Ghi de bang rename(2) (mv) la an toan tren Linux: tien trinh dang chay
#   giu inode cu (binary, font, lang dang mo van con nguyen), cac file moi
#   chi co hieu luc o lan mo app tiep theo. Khong can co che stage/swap
#   phuc tap hon.
#
# Dung: sh ota-update.sh --apply | sh ota-update.sh --check | sh ota-update.sh
# --apply: cai ngay khong hoi (launch.sh goi nen). --check: chi bao co ban moi
# khong. Khong doi so: hoi y/N. Tat han: FILEMANAGER_NO_OTA=1.
case "$0" in
  */*)
    cd "$(dirname "$0")" || exit 1
    ;;
esac
APP="$(pwd)"
VERSION_FILE="$APP/VERSION"
CUR="$(cat "$VERSION_FILE" 2>/dev/null | tr -d ' \r\n')"
[ -n "$CUR" ] || CUR="0.0.0"
REPO="nlkcodenew/vtree-spruce"
RAW_BASE="https://raw.githubusercontent.com"
JSDELIVR_MANIFEST="https://cdn.jsdelivr.net/gh/$REPO@main/ota/manifest.json"
LOG="$APP/ota.log"
TMPD="/tmp/filemanager-ota-stage"
MANIFEST_JSON="$TMPD/manifest.json"
LOCKD="/tmp/filemanager-ota-lock"
# May TrimUI khong co CA he thong (/etc/ssl/certs trong): curl loi 60, wget loi 5.
# Dung bundle CA di kem (certs/cacert.pem) neu co; curl tu nhan bien CURL_CA_BUNDLE.
CA_BUNDLE="$APP/certs/cacert.pem"
if [ -f "$CA_BUNDLE" ]; then
  export CURL_CA_BUNDLE="$CA_BUNDLE"
  WGET_CACERT="--ca-certificate=$CA_BUNDLE"
else
  WGET_CACERT=""
fi
say() { echo "[ota] $*"; echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) $*" >> "$LOG" 2>/dev/null; }

clean_tmp() { rm -rf "$TMPD" 2>/dev/null || true; }

# Du lieu nguoi dung / runtime: khong tai, khong chep de.
# (VERSION duoc ghi rieng sau khi cai xong, khong lay tu zip.)
is_protected() {
  case "$1" in
    config.ini|*.log|VERSION|.ota-staged/*) return 0;;
  esac
  return 1
}

# So sanh version dang x.y... (bo hau to chu khi so). Tra 0 = a moi hon b.
ver_newer() {
  a="$1"; b="$2"
  [ "$a" = "$b" ] && return 1
  i=1
  while :; do
    pa="$(echo "$a" | cut -d. -f$i 2>/dev/null)"; pb="$(echo "$b" | cut -d. -f$i 2>/dev/null)"
    [ -z "$pa$pb" ] && break
    pa="${pa%%[!0-9]*}"; pb="${pb%%[!0-9]*}"
    [ -z "$pa" ] && pa=0; [ -z "$pb" ] && pb=0
    pa="$(echo "$pa" | sed 's/^0*//')"; pb="$(echo "$pb" | sed 's/^0*//')"
    [ -z "$pa" ] && pa=0; [ -z "$pb" ] && pb=0
    if [ "$pa" -gt "$pb" ] 2>/dev/null; then return 0; fi
    if [ "$pa" -lt "$pb" ] 2>/dev/null; then return 1; fi
    i=$((i + 1))
    [ "$i" -gt 8 ] && break
  done
  return 1
}

fetch() {
  url="$1"; out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 8 --max-time 60 --retry 0 -o "$out" "$url" 2>/dev/null && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q $WGET_CACERT --timeout=60 --tries=1 -O "$out" "$url" 2>/dev/null && return 0
  fi
  return 1
}

# Trich 1 field string don gian tu manifest JSON (da duoc verify chu ky).
json_field() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$MANIFEST_JSON" 2>/dev/null \
    | head -n 1 | sed 's/.*"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

MODE="${1:-}"
if [ -n "${FILEMANAGER_NO_OTA:-}" ] && [ "$FILEMANAGER_NO_OTA" != "0" ]; then
  [ "$MODE" = "--apply" ] || say "Da tat OTA (FILEMANAGER_NO_OTA=1)."
  exit 0
fi

acquire_lock() {
  if mkdir "$LOCKD" 2>/dev/null; then
    echo "$$" > "$LOCKD/pid" 2>/dev/null
    return 0
  fi
  old="$(cat "$LOCKD/pid" 2>/dev/null)"
  case "$old" in
    ''|*[!0-9]*) ;;
    *) kill -0 "$old" 2>/dev/null && return 1;;
  esac
  rm -rf "$LOCKD" 2>/dev/null
  mkdir "$LOCKD" 2>/dev/null || return 1
  echo "$$" > "$LOCKD/pid" 2>/dev/null
}
if ! acquire_lock; then
  say "Trinh cap nhat dang chay"
  exit 4
fi
trap 'rm -rf "$LOCKD" 2>/dev/null' EXIT INT TERM
clean_tmp
mkdir -p "$TMPD" 2>/dev/null || { say "Khong tao duoc thu muc tam"; exit 1; }
say "local=$CUR"

got_manifest=0
for try in 1 2; do
  if fetch "$RAW_BASE/$REPO/main/ota/manifest.json" "$MANIFEST_JSON"; then
    got_manifest=1; break
  fi
  if fetch "$JSDELIVR_MANIFEST" "$MANIFEST_JSON"; then
    got_manifest=1; break
  fi
  [ "$try" = "1" ] && sleep 3
done
[ "$got_manifest" = "1" ] || { say "Khong tai duoc manifest"; clean_tmp; exit 1; }

# BAT BUOC binary verify chu ky Ed25519 truoc khi tin manifest.
if [ ! -x "$APP/vtree.aarch64" ] || ! "$APP/vtree.aarch64" --verify-manifest "$MANIFEST_JSON" >> "$LOG" 2>&1; then
  say "Chu ky manifest khong hop le"
  clean_tmp
  exit 1
fi

REM="$(json_field version)"
[ -n "$REM" ] || { say "Manifest thieu version"; clean_tmp; exit 1; }
say "remote=$REM"
if ! ver_newer "$REM" "$CUR"; then
  say "Da la ban moi nhat ($CUR)"
  clean_tmp
  exit 2
fi
if [ "$MODE" = "--check" ]; then
  say "Co ban moi: $REM (dang dung $CUR)."
  clean_tmp
  exit 10
fi
if [ "$MODE" != "--apply" ]; then
  printf "Co ban moi %s (hien tai %s). Cap nhat? [y/N] " "$REM" "$CUR"
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) say "Da huy"; clean_tmp; exit 3;; esac
fi

# Manifest chi co 1 file payload (FileManagement.zip). Lay url/sha256/size
# tu manifest DA VERIFY — khong tin bat ky gia tri nao truoc buoc verify.
ZIP_URL="$(json_field url)"
ZIP_SHA="$(json_field sha256)"
ZIP_SIZE="$(grep -o '"size"[[:space:]]*:[[:space:]]*[0-9]*' "$MANIFEST_JSON" 2>/dev/null | head -n 1 | grep -o '[0-9]*$')"
[ -n "$ZIP_URL" ] && [ -n "$ZIP_SHA" ] && [ -n "$ZIP_SIZE" ] || { say "Manifest thieu thong tin file"; clean_tmp; exit 1; }
case "$ZIP_SHA" in
  *[!0-9a-fA-F]*|"") say "sha256 khong hop le"; clean_tmp; exit 1;;
esac
[ "${#ZIP_SHA}" = "64" ] || { say "sha256 khong hop le"; clean_tmp; exit 1; }
case "$ZIP_URL" in
  https://*) ;;
  *) say "URL khong hop le"; clean_tmp; exit 1;;
esac

say "Dang tai $REM ..."
if ! fetch "$ZIP_URL" "$TMPD/FileManagement.zip"; then
  say "Khong tai duoc FileManagement.zip"
  clean_tmp
  exit 1
fi
command -v sha256sum >/dev/null 2>&1 || { say "Thieu sha256sum"; clean_tmp; exit 1; }
have="$(sha256sum "$TMPD/FileManagement.zip" 2>/dev/null | cut -d' ' -f1)"
if [ "$have" != "$ZIP_SHA" ]; then
  say "Sai ma kiem tra FileManagement.zip"
  clean_tmp
  exit 1
fi
say "ok FileManagement.zip"

# Giai nen vao thu muc tam. Dung unzip (busybox) neu co, neu khong dung
# bin/7zz di kem app.
UNZIPD="$TMPD/unzipped"
mkdir -p "$UNZIPD" 2>/dev/null || { say "Khong tao duoc thu muc tam"; clean_tmp; exit 1; }
if command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$TMPD/FileManagement.zip" -d "$UNZIPD" 2>/dev/null || { say "Giai nen that bai"; clean_tmp; exit 1; }
elif [ -x "$APP/bin/7zz" ]; then
  "$APP/bin/7zz" x -y -o"$UNZIPD" "$TMPD/FileManagement.zip" >/dev/null 2>&1 || { say "Giai nen that bai"; clean_tmp; exit 1; }
else
  say "Thieu cong cu giai nen (unzip/7zz)"
  clean_tmp
  exit 1
fi

# Cai atomic tung file: chi chep file co trong zip, bo qua file bao ve.
# File user tu them trong fonts//lang/ khong co trong zip nen tu dong duoc giu.
# Release zip that co top-level FileManagement/ (build-app.yml: zip -r FileManagement.zip FileManagement);
# zip test phang thi khong. Xac dinh payload root de khong cai nham vao $APP/FileManagement/.
PAYLOAD_ROOT="$UNZIPD"
if [ -d "$UNZIPD/FileManagement" ]; then
  PAYLOAD_ROOT="$UNZIPD/FileManagement"
fi
APPLY_FAIL=0
(cd "$PAYLOAD_ROOT" && find . -type f -print > "$TMPD/apply.list") || { say "Cai dat that bai"; clean_tmp; exit 1; }
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#./}"
  if is_protected "$rel"; then continue; fi
  [ -f "$PAYLOAD_ROOT/$rel" ] || continue
  dst="$APP/$rel"
  mkdir -p "$(dirname "$dst")" 2>/dev/null
  tmp="$dst.ota-new"
  if ! cp "$PAYLOAD_ROOT/$rel" "$tmp" 2>/dev/null; then say "Chep that bai: $rel"; APPLY_FAIL=1; break; fi
  case "$rel" in *.sh|bin/*) chmod +x "$tmp" 2>/dev/null;; esac
  if ! mv "$tmp" "$dst" 2>/dev/null; then say "Cai dat that bai: $rel"; APPLY_FAIL=1; break; fi
  say "installed $rel"
done < "$TMPD/apply.list"
if [ "$APPLY_FAIL" != "0" ]; then clean_tmp; exit 1; fi

printf "%s" "$REM" | tr -d " \r\n" > "$APP/VERSION" 2>/dev/null
say "Cap nhat xong $CUR -> $REM (co hieu luc o lan mo app tiep theo)."
clean_tmp
exit 0
