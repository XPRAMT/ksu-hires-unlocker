#!/system/bin/sh
# Late-start reload after a soft reboot. On a KernelSU soft reboot the audio HAL / audioserver can start
# before the mount module has mounted the overlay, so they keep the stock libraries and config (USB/BT
# stuck at 48 kHz). Cold boot is not affected (the overlay is mounted in post-fs-data). This script waits
# for the overlay to be visible, then checks which inode each audio process really maps, and restarts the
# stale services once per boot. It does nothing if the overlay never appears or nothing is stale.
MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/device.sh"
P=${PROC:-/proc}
LOG=$MODDIR/service.log
APM=/system/lib64/libaudiopolicymanagerdefault.so
AS=/system/bin/audioserver
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
: > "$LOG"
[ -f "$MODDIR/skip_mount" ] && { log "skip_mount set: nothing to do"; exit 0; }
[ -f "$MODDIR/disable" ] && { log "module disabled: nothing to do"; exit 0; }
WAIT=${WAIT_S:-90}

# overlay visible = live files have the same content as the module copies (any mount module)
mounted() { cmp -s "$MODDIR/system/$XML_REL" "$XML" && cmp -s "$MODDIR/system/lib64/libaudiopolicymanagerdefault.so" "$APM"; }
i=0
until mounted; do
  i=$((i + 1)); [ $i -gt "$WAIT" ] && { log "overlay not visible after ${WAIT}s (mount module did not mount?): nothing done"; exit 0; }
  sleep 1
done
i=0
until [ "$(getprop sys.boot_completed)" = 1 ] || [ $i -ge "$WAIT" ]; do i=$((i + 1)); sleep 1; done

ino() { stat -L -c %i "$1" 2>/dev/null; }
# maps_stale <pid> <path>: the process maps <path> with an inode other than the live (overlay) file
maps_stale() { awk -v p="$2" -v i="$(ino "$2")" '$6 == p && $5 != i { s = 1 } END { exit !s }' "$P/$1/maps" 2>/dev/null; }
svc_pid() { p=$(getprop "init.svc_debug_pid.$1"); [ -n "$p" ] || p=$(pidof "$2" 2>/dev/null | cut -d' ' -f1); echo "$p"; }
check() {
  stale=""
  if [ -n "$RELOAD_HAL_SVC" ]; then
    hp=$(svc_pid "$RELOAD_HAL_SVC" "$RELOAD_HAL_BIN")
    [ -n "$hp" ] && maps_stale "$hp" "$RELOAD_HAL_LIB" && stale="hal"
  fi
  ap=$(svc_pid audioserver audioserver)
  if [ -n "$ap" ] && { maps_stale "$ap" "$APM" || [ "$(ino "$P/$ap/exe")" != "$(ino "$AS")" ]; }; then
    stale="$stale audioserver"
  fi
}
check
[ -z "$stale" ] && { log "overlay mounted, audio processes use it: nothing to do"; exit 0; }
tok=$(cat "$MODDIR/.boot" 2>/dev/null); tok=${tok:-unknown}
if [ "$(cat "$MODDIR/.reloaded" 2>/dev/null)" = "$tok" ]; then
  log "stale:$stale, but already reloaded this boot: giving up"; exit 0
fi
echo "$tok" > "$MODDIR/.reloaded"
log "stale:$stale (started before the overlay was mounted): restarting"
case " $stale " in *" hal "*)
  log "setprop ctl.restart $RELOAD_HAL_SVC"; setprop ctl.restart "$RELOAD_HAL_SVC"; sleep 3 ;;
esac
log "setprop ctl.restart audioserver"; setprop ctl.restart audioserver   # also re-reads the HAL ports
sleep 3
check
[ -z "$stale" ] && log "reload ok" || log "still stale:$stale"