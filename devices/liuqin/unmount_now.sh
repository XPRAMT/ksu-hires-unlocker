#!/system/bin/sh
# Reverts mount_now.sh: removes the three bind mounts (global namespace) and restarts audioserver on
# the stock files. usage (root): sh /data/adb/modules/bt_hires_mixer_liuqin/unmount_now.sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
NS=""; command -v nsenter >/dev/null && NS="nsenter -t 1 -m --"
for t in "$XML" /system/lib64/libaudiopolicymanagerdefault.so /system/bin/audioserver; do
  n=0; while $NS grep -q " $t " /proc/self/mountinfo && [ $n -lt 5 ]; do $NS umount "$t" && echo "  umount $t"; n=$((n+1)); done
done
$NS sh -c "umount /dev/bt_hires_stage 2>/dev/null; rmdir /dev/bt_hires_stage 2>/dev/null"
old=$(pidof audioserver); kill $old 2>/dev/null; sleep 3
echo "- audioserver pid ${old:-none} -> $(pidof audioserver)"
sha256sum "$XML" /system/lib64/libaudiopolicymanagerdefault.so /system/bin/audioserver