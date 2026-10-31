#!/system/bin/sh
# For a temporary root (KernelSU injected after boot): a soft/userspace restart runs post-fs-data.sh
# but does NOT mount the module, and a full reboot loses root. This script bind-mounts the module's
# three files over the stock ones in the global mount namespace and restarts only audioserver.
# Any failure reverts every mount (and restarts audioserver again if it was already restarted).
# usage (root): sh /data/adb/modules/bt_hires_mixer_liuqin/mount_now.sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/guard.conf" || { echo "! guard.conf missing"; exit 1; }
NS=""; command -v nsenter >/dev/null && NS="nsenter -t 1 -m --"
APM_T=/system/lib64/libaudiopolicymanagerdefault.so
AS_T=/system/bin/audioserver
SRC_XML="$MODDIR/$XML_REL"; [ -L "$MODDIR/system/vendor" ] || [ -f "$SRC_XML" ] || SRC_XML="$MODDIR/system/$XML_REL"
SRC_APM="$MODDIR/system/lib64/libaudiopolicymanagerdefault.so"
SRC_AS="$MODDIR/system/bin/audioserver"
STAGE=/dev/bt_hires_stage   # tmpfs without nosuid: a bind mount keeps the source mount flags, and
                            # /data is nosuid, so init cannot exec audioserver from it (nosuid_transition)
MOUNTED=""
log() { echo "$*"; }
in_ns() { $NS sh -c "$1"; }
sha_ns() { in_ns "sha256sum '$1'" | cut -d' ' -f1; }
undo() {
  for t in $MOUNTED; do in_ns "umount '$t'" && log "  umount $t"; done
  MOUNTED=""
  in_ns "umount $STAGE 2>/dev/null; rmdir $STAGE 2>/dev/null"
}
fail() { log "! $*"; undo; [ -n "$RESTARTED" ] && { killall audioserver 2>/dev/null; log "  audioserver restarted on stock files"; }; exit 1; }
as_pid() { pidof audioserver | cut -d' ' -f1; }
crashes() { logcat -b crash -d 2>/dev/null | grep -c '>>> /system/bin/audioserver <<<'; }

[ "$(getprop ro.product.device)" = "$REQ_DEVICE" ] || fail "wrong device"
[ "$(getprop ro.build.version.sdk)" = "$REQ_SDK" ] || fail "wrong SDK"
# module copies must be the patched builds of the current stock files
[ "$(sha256sum "$SRC_XML" | cut -d' ' -f1)" = "$XML_OUT_SHA" ] || fail "module xml SHA mismatch"
[ "$(stock_sha "$SRC_APM" "$APM_OLD_OCT" $APM_OFFS)" = "$APM_STOCK_SHA" ] || fail "module APM SHA mismatch"
[ "$(stock_sha "$SRC_AS" "$AS_OLD_OCT" $AS_OFFS)" = "$AS_STOCK_SHA" ] || fail "module audioserver SHA mismatch"
grep -q deep_buffer_rate_ "$XML" && fail "already mounted (run unmount_now.sh first)"
[ "$(sha256sum "$XML" | cut -d' ' -f1)" = "$XML_STOCK_SHA" ] || fail "stock xml changed (ROM update?)"
[ "$(sha256sum $APM_T | cut -d' ' -f1)" = "$APM_STOCK_SHA" ] || fail "stock APM changed"
[ "$(sha256sum $AS_T | cut -d' ' -f1)" = "$AS_STOCK_SHA" ] || fail "stock audioserver changed"
# SELinux labels of the copies = labels of the stock files (only the copies are relabelled)
for p in "$SRC_XML:$XML" "$SRC_APM:$APM_T" "$SRC_AS:$AS_T"; do
  s=${p%%:*}; t=${p#*:}
  want=$(ls -Z "$t" | awk '{print $1}'); have=$(ls -Z "$s" | awk '{print $1}')
  [ "$want" = "$have" ] || { chcon "$want" "$s" || fail "chcon $s"; log "  chcon $want $s"; }
done
log "- staging on tmpfs $STAGE"
in_ns "mkdir -p $STAGE && mount -t tmpfs -o mode=0755,suid,exec tmpfs $STAGE" || fail "tmpfs"
for s in "$SRC_XML" "$SRC_APM" "$SRC_AS"; do
  d="$STAGE/${s##*/}"
  in_ns "cp -p '$s' '$d' && chcon \$(ls -Z '$s' | awk '{print \$1}') '$d' && chown \$(stat -c %u:%g '$s') '$d'" || fail "stage $s"
done
SRC_XML="$STAGE/${SRC_XML##*/}"; SRC_APM="$STAGE/${SRC_APM##*/}"; SRC_AS="$STAGE/${SRC_AS##*/}"
log "- bind mounts (namespace: ${NS:-current})"
for p in "$SRC_XML:$XML:$XML_OUT_SHA" "$SRC_APM:$APM_T:" "$SRC_AS:$AS_T:"; do
  s=${p%%:*}; r=${p#*:}; t=${r%%:*}
  want=$(sha256sum "$s" | cut -d' ' -f1)
  in_ns "mount --bind '$s' '$t'" || fail "mount $t"
  MOUNTED="$t $MOUNTED"
  [ "$(sha_ns "$t")" = "$want" ] || fail "SHA after mount $t"
  log "  $t -> $want"
done
log "- restart audioserver"
c0=$(crashes); old=$(as_pid); RESTARTED=1
kill "$old" 2>/dev/null
i=0; new=""
while [ $i -lt 20 ]; do sleep 1; i=$((i+1)); new=$(as_pid); [ -n "$new" ] && [ "$new" != "$old" ] && break; done
[ -n "$new" ] && [ "$new" != "$old" ] || fail "audioserver did not come back"
log "  pid $old -> $new"
for t in "$XML" "$APM_T" "$AS_T"; do log "  ns(pid $new) $(sha256sum /proc/$new/root$t | cut -d' ' -f1) $t"; done
[ "$(sha256sum /proc/$new/root$XML | cut -d' ' -f1)" = "$XML_OUT_SHA" ] || fail "new audioserver does not see the overlay"
log "- watching 60 s"
changes=0; cur=$new; i=0
while [ $i -lt 60 ]; do
  sleep 5; i=$((i+5)); p=$(as_pid)
  [ "$p" != "$cur" ] && { changes=$((changes+1)); cur=$p; log "  pid changed -> $p"; }
  [ $changes -ge 3 ] && fail "audioserver restart loop"
done
c1=$(crashes)
[ "$changes" -eq 0 ] && [ "$c1" -eq "$c0" ] || fail "audioserver unstable (pid changes $changes, crashes $c0 -> $c1)"
log "- OK: audioserver pid $cur stable, overlay active"