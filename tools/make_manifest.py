#!/usr/bin/env python3
"""make_manifest.py — sinh + ky Ed25519 ota/manifest.json cho FileManagement (vTree).

Mo hinh hoc tu Trimui-LocalSend (tools/make_manifest.py):
  - private key ky release giu OFFLINE tren may dev, KHONG commit
  - binary tren may chi nhung public key (kid fm1)
  - canonical body phai khop tung byte voi ota_verify_manifest() trong fileop.c:
      {"files":[{"path":..,"sha256":..,"size":N}],"kid":"..","version":".."}
    (files sap xep theo path, JSON gon khong khoang trang, key sap xep)

Khac LocalSend: payload chi 1 file duy nhat (FileManagement.zip lay tu
GitHub Release asset), khong phai duyet thu muc.

Ky bang openssl CLI (khong can lib cryptography):
  openssl pkeyutl -sign -inkey <key.pem> -rawin -in <canonical.bin>

Dung:
  python3 tools/make_manifest.py --version 1.3.0 --zip /path/to/FileManagement.zip
      [--key ~/.config/vtree-spruce/ota/fm1.key] [--kid fm1]
      [--out ota/manifest.json] [--url URL-ghi-de]

Quy trinh publish:
  1. merge + tag release (vd v1.3.0), workflow build ra FileManagement.zip
  2. tai FileManagement.zip tu Release asset ve may
  3. chay tool nay -> ota/manifest.json (da ky)
  4. commit + push ota/manifest.json len main
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys


def b64url_nopad(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--zip", required=True,
                    help="FileManagement.zip (tu Release asset)")
    ap.add_argument("--key",
                    default="~/.config/vtree-spruce/ota/fm1.key",
                    help="private key Ed25519 (PEM, offline)")
    ap.add_argument("--kid", default="fm1")
    ap.add_argument("--out", default="ota/manifest.json")
    ap.add_argument("--url", default="",
                    help="URL tai FileManagement.zip (mac dinh dung GitHub release asset theo version)")
    args = ap.parse_args()

    key = os.path.expanduser(args.key)
    if not os.path.isfile(key):
        print("khong tim thay private key: " + key, file=sys.stderr)
        return 1
    if not os.path.isfile(args.zip):
        print("khong tim thay zip: " + args.zip, file=sys.stderr)
        return 1

    with open(args.zip, "rb") as f:
        data = f.read()
    url = args.url
    if not url:
        url = ("https://github.com/nlkcodenew/vtree-spruce/releases/download/"
               "v%s/FileManagement.zip" % args.version)
    entry = {
        "path": "FileManagement.zip",
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
        "url": url,
    }

    body_obj = {"files": [entry], "kid": args.kid, "version": args.version}
    # sort_keys=True cho {"files","kid","version"} dung thu tu canonical.
    # ensure_ascii=False: byte UTF-8 di thang, khop oj_sb_jescape() ben C
    # (chi escape ", \, va ky tu dieu khien).
    body = json.dumps(body_obj, separators=(",", ":"),
                      sort_keys=True, ensure_ascii=False).encode("utf-8")

    # Ky bang openssl CLI (Ed25519: ky "raw", khong pre-hash).
    with open("/tmp/fm_canonical.bin", "wb") as f:
        f.write(body)
    try:
        sig = subprocess.run(
            ["openssl", "pkeyutl", "-sign", "-inkey", key,
             "-rawin", "-in", "/tmp/fm_canonical.bin"],
            capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print("ky that bai: %s" % e, file=sys.stderr)
        return 1
    finally:
        try:
            os.remove("/tmp/fm_canonical.bin")
        except OSError:
            pass
    if len(sig.stdout) != 64:
        print("chu ky khong phai 64 byte", file=sys.stderr)
        return 1

    manifest = dict(body_obj)
    manifest["signature"] = b64url_nopad(sig.stdout)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print("version=%s files=1 -> %s" % (args.version, args.out))
    print("canonical_sha256=%s" % hashlib.sha256(body).hexdigest())
    print("zip_sha256=%s size=%d" % (entry["sha256"], entry["size"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
