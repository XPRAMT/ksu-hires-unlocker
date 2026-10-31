#!/bin/bash
# Smoke test of a built module zip on a Linux PC (no device needed): fake stock files, then install,
# boot guard with stock files, boot guard with the patched files mounted, reinstall over the mounted
# files, and boot guard after a ROM change (must skip_mount).
# usage: tools/selftest/run.sh <device> <zip>
set -u
dev=$1; zip=$(readlink -f "$2"); H=$(cd "$(dirname "$0")" && pwd)
O=$(mktemp -d); M=$O/mod; R=$O/root
mkdir -p "$M" "$O/bin" "$R/data/adb" "$O/tmp"; (cd "$M" && unzip -q "$zip")
python3 "$H/mkfix.py" "$dev" "$R"
for f in "$M"/*.sh; do sed -i -E "s#(^|[ \"=:])/(system|vendor|data/adb)/#\\1$R/\\2/#g" "$f"; done
printf '#!/bin/sh\necho "resetprop $*"\n' > "$O/bin/resetprop"; chmod +x "$O/bin/resetprop"
export PATH="$O/bin:$PATH" TMPDIR="$O/tmp"
STUB='ui_print(){ echo "UI: $*"; }; abort(){ echo "ABORT: $*"; exit 1; }; set_perm(){ echo "PERM $*"; }; set_perm_recursive(){ echo "PERMR $*"; }; getprop(){ case $1 in ro.product.model) echo NX809J;; ro.product.device) echo liuqin;; ro.build.version.sdk) [ '"$dev"' = nx809j ] && echo 36 || echo 35;; esac; }'
boot() { sh -c "$STUB; . $M/post-fs-data.sh" "$M/post-fs-data.sh"; [ -f "$M/skip_mount" ] && echo "skip_mount" || echo "mount"; }
echo "== install"; ( eval "$STUB"; MODPATH=$M; . "$M/customize.sh" ) 2>&1
echo "== guard"; cat "$M/guard.conf"
echo "== boot (stock)"; boot
cp "$M/system/lib64/libaudiopolicymanagerdefault.so" "$R/system/lib64/"; cp "$M/system/bin/audioserver" "$R/system/bin/"
[ -d "$M/system/vendor/lib64" ] && cp -r "$M/system/vendor/lib64" "$R/vendor/"; cp -r "$M/system/vendor/etc" "$R/vendor/"
echo "== boot (patched files mounted)"; boot
echo "== reinstall over the mounted files"; ( eval "$STUB"; MODPATH=$M; . "$M/customize.sh" ) 2>&1 | grep -E 'ABORT|^UI: !' || echo ok
printf 'x' >> "$R/system/bin/audioserver"
echo "== boot (ROM changed, expect skip_mount)"; boot
rm -rf "$O"
