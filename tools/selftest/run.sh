#!/bin/bash
# Smoke test of a built module zip on a Linux PC (no device needed): fake stock files, then install,
# boot guard with stock files, boot guard with the patched files mounted, reinstall over the mounted
# files, boot guard after a ROM change (must skip_mount), and service.sh (soft-reboot reload) with fake
# /proc entries: mount never appears, fresh processes, stale processes, once-per-boot guard.
# usage: tools/selftest/run.sh <device> <zip>
set -u
dev=$1; zip=$(readlink -f "$2"); H=$(cd "$(dirname "$0")" && pwd)
O=$(mktemp -d); M=$O/mod; R=$O/root
mkdir -p "$M" "$O/bin" "$R/data/adb" "$O/tmp"; (cd "$M" && { unzip -q "$zip" 2>/dev/null || python3 -m zipfile -e "$zip" .; })
python3 "$H/mkfix.py" "$dev" "$R"
for f in "$M"/*.sh; do sed -i -E "s#(^|[ \"=:])/(system|vendor|data/adb)/#\\1$R/\\2/#g" "$f"; done
printf '#!/bin/sh\necho "resetprop $*"\n' > "$O/bin/resetprop"; chmod +x "$O/bin/resetprop"
export PATH="$O/bin:$PATH" TMPDIR="$O/tmp"
STUB='ui_print(){ echo "UI: $*"; }; abort(){ echo "ABORT: $*"; exit 1; }; set_perm(){ echo "PERM $*"; }; set_perm_recursive(){ echo "PERMR $*"; }; getprop(){ case $1 in ro.product.model) echo NX809J;; ro.product.device) echo liuqin;; ro.build.version.sdk) [ '"$dev"' = nx809j ] && echo 36 || echo 35;; sys.boot_completed) echo 1;; init.svc_debug_pid.audioserver) echo 100;; init.svc_debug_pid.vendor.audio-hal-aidl) echo 200;; esac; }'
boot() { sh -c "$STUB; . $M/post-fs-data.sh" "$M/post-fs-data.sh"; [ -f "$M/skip_mount" ] && echo "skip_mount" || echo "mount"; }
# fake /proc: pid 100 audioserver, pid 200 HAL; "fresh" maps the live files, "stale" the stock copies
PR=$O/proc; mkdir -p "$PR/100" "$PR/200" "$O/stock"
cp "$R/system/lib64/libaudiopolicymanagerdefault.so" "$R/system/bin/audioserver" "$O/stock/"
[ -f "$R/vendor/lib64/hw/libaudiocorehal.qti.so" ] && cp "$R/vendor/lib64/hw/libaudiocorehal.qti.so" "$O/stock/"
cat > "$O/bin/mkproc" <<EOF
#!/bin/sh
# mkproc <100|200> <fresh|stale>
ino() { stat -L -c %i "\$1"; }
if [ "\$1" = 100 ]; then lib=$R/system/lib64/libaudiopolicymanagerdefault.so; st=$O/stock/libaudiopolicymanagerdefault.so
  [ "\$2" = fresh ] && ln -sf $R/system/bin/audioserver $PR/100/exe || ln -sf $O/stock/audioserver $PR/100/exe
else lib=$R/vendor/lib64/hw/libaudiocorehal.qti.so; st=$O/stock/libaudiocorehal.qti.so; [ -f \$st ] || exit 0; fi
[ "\$2" = fresh ] && i=\$(ino \$lib) || i=\$(ino \$st)
echo "7000-8000 r-xp 00000000 fe:11 \$i \$lib" > $PR/\$1/maps
EOF
printf '#!/bin/sh\necho "SETPROP $*"\ncase $2 in audioserver) mkproc 100 fresh;; vendor.audio-hal-aidl) mkproc 200 fresh;; esac\n' > "$O/bin/setprop"
chmod +x "$O/bin/mkproc" "$O/bin/setprop"
svc() { PROC=$PR WAIT_S=3 sh -c "$STUB; sleep(){ :; }; . $M/service.sh" "$M/service.sh"; cat "$M/service.log"; }
echo "== install"; ( eval "$STUB"; MODPATH=$M; . "$M/customize.sh" ) 2>&1
echo "== guard"; cat "$M/guard.conf"
echo "== boot (stock)"; boot
echo "== service (mount never appears, expect nothing done)"; svc
cp "$M/system/lib64/libaudiopolicymanagerdefault.so" "$R/system/lib64/"; cp "$M/system/bin/audioserver" "$R/system/bin/"
[ -d "$M/system/vendor/lib64" ] && cp -r "$M/system/vendor/lib64" "$R/vendor/"; cp -r "$M/system/vendor/etc" "$R/vendor/"
echo "== boot (patched files mounted)"; boot
mkproc 100 fresh; mkproc 200 fresh
echo "== service (cold boot, fresh, expect nothing to do)"; svc
mkproc 100 stale; mkproc 200 stale
echo "== service (soft reboot, stale, expect restart)"; svc
mkproc 100 stale; mkproc 200 stale
echo "== service (stale again same boot, expect giving up)"; svc
boot; echo "== service (next boot, stale, expect restart)"; svc
echo "== reinstall over the mounted files"; ( eval "$STUB"; MODPATH=$M; . "$M/customize.sh" ) 2>&1 | grep -E 'ABORT|^UI: !' || echo ok
printf 'x' >> "$R/system/bin/audioserver"
echo "== boot (ROM changed, expect skip_mount)"; boot
rm -rf "$O"
