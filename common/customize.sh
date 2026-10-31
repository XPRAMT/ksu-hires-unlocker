#!/system/bin/sh
# Installer (shared by every device). The device is described by device.sh. Nothing vendor-owned is
# shipped in the zip: the patched libraries and the mix-port config are built here from the device's
# own files. Patch sites are found by their instruction bytes and must match exactly, otherwise the
# install aborts.
SRCDIR=${MODPATH:-${0%/*}}
. "$SRCDIR/common.sh"
. "$SRCDIR/device.sh"
: "${SRCXML:=$XML}"
: "${LIB:=/system/lib64/libaudiopolicymanagerdefault.so}"
: "${AS:=/system/bin/audioserver}"
: "${STOCKDIR:=$STOCKDIR_DEFAULT}"
: "${DEVICE:=$(getprop $REQ_PROP)}"
: "${SDK:=$(getprop ro.build.version.sdk)}"
VERSION=$(sed -n 's/^version=//p' "$SRCDIR/module.prop")

[ "$DEVICE" = "$REQ_VAL" ] || abort "! Unsupported device '$DEVICE' (this module is for $REQ_VAL only)."
[ "$SDK" = "$REQ_SDK" ] || abort "! Unsupported Android version (SDK $SDK, need Android $REQ_ANDROID = SDK $REQ_SDK)."

# build_lib <source> <dest> <old hex> <new hex> <old oct> <new oct> <bytes before the patch> <exact site count> <name>
# Copies the library and patches every site (or keeps it if already patched). Records the patch
# offsets and the stock-equivalent SHA-256 in $GUARD for the boot-time check.
build_lib() {
  src=$1; dst=$2; oh=$3; nh=$4; oo=$5; no=$6; skip=$7; need=$8; name=$9
  set -- $(find_pat "$src" "$oh"); co=$1; shift; po="$*"
  set -- $(find_pat "$src" "$nh"); cn=$1; shift; pn="$*"
  mkdir -p "${dst%/*}" || abort "! Cannot create ${dst%/*}"
  cp "$src" "$dst" || abort "! Cannot copy $src"
  tot=$((co + cn))
  if [ "$tot" -eq "$need" ]; then
    offs=""; for o in $po $pn; do offs="$offs $((o + skip))"; done
    if [ "$co" -gt 0 ]; then                                 # patch the sites that are still stock
      stk=""; for o in $po; do stk="$stk $((o + skip))"; done
      patch_at "$dst" "$no" $stk || abort "! Patch of $dst failed."
    fi
  else
    ui_print "! $src: patch site not found as expected (stock x$co, patched x$cn)"
    abort "! Aborted: this build is not supported, module not installed."
  fi
  set -- $(find_pat "$dst" "$oh"); [ "$1" = 0 ] || abort "! Patch of $dst failed."
  set -- $(find_pat "$dst" "$nh"); [ "$1" -ge 1 ] || abort "! Patch of $dst failed."
  echo "${name}_OFFS=\"$offs\"" >> "$GUARD"
  echo "${name}_STOCK_SHA=$(stock_sha "$dst" "$oo" $offs)" >> "$GUARD"
}

GUARD="$SRCDIR/guard.conf"
: > "$GUARD"
ui_print "- $DEV_LABEL $VERSION ($DEVICE, Android $REQ_ANDROID)"

ui_print "  * audio policy library"
build_lib "$LIB" "$SRCDIR/system/lib64/libaudiopolicymanagerdefault.so" "$APM_OLD_HEX" "$APM_NEW_HEX" "$APM_OLD_OCT" "$APM_NEW_OCT" 0 1 APM
if [ "$HAS_HAL" = 1 ]; then
  ui_print "  * audio HAL library"
  build_lib "$HAL" "$SRCDIR/system/$HAL_REL" "$HAL_OLD_HEX" "$HAL_NEW_HEX" "$HAL_OLD_OCT" "$HAL_NEW_OCT" $HAL_SKIP $HAL_COUNT HAL
fi

ui_print "  * audio server (A2DP standby floor)"
build_lib "$AS" "$SRCDIR/system/bin/audioserver" "$AS_OLD_HEX" "$AS_NEW_HEX" "$AS_OLD_OCT" "$AS_NEW_OCT" $AS_SKIP 1 AS

ui_print "  * $XML_LABEL"
mkdir -p "$STOCKDIR"
if grep -q 'deep_buffer_rate_' "$SRCXML"; then               # this module's config is currently mounted
  [ -f "$STOCKDIR/$XML_NAME" ] || abort "! Stock config backup missing: disable the module, reboot, then install again."
else
  cp "$SRCXML" "$STOCKDIR/$XML_NAME" || abort "! Cannot back up $SRCXML"
fi
OUTXML="$SRCDIR/system/$XML_REL"
mkdir -p "${OUTXML%/*}"
gen_xml "$STOCKDIR/$XML_NAME" "$OUTXML" || abort "! The audio config layout is not supported ($XML_ERR)."
grep -q 'deep_buffer_rate_192k_out' "$OUTXML" || abort "! Generated config is incomplete."
echo "XML_STOCK_SHA=$(sha256sum "$STOCKDIR/$XML_NAME" | cut -d' ' -f1)" >> "$GUARD"
echo "XML_OUT_SHA=$(sha256sum "$OUTXML" | cut -d' ' -f1)" >> "$GUARD"

ui_print "  * per-rate deep-buffer mix ports: 44.1/48/88.2/96 kHz for Bluetooth A2DP, plus 176.4/192 kHz for wired headphones and USB audio"
ui_print "  * audio policy: score the sampling rate for requests <= 48 kHz too"
[ "$HAS_HAL" = 1 ] && ui_print "  * audio HAL: deep-buffer buffer rounded up to 16 frames (fixes 44.1/88.2 kHz crackle)"
ui_print "  * AudioFlinger: standby delay ${STANDBY_MS} ms (also on Bluetooth) so a new sample rate starts sooner"
set_perm_recursive "$SRCDIR/system/vendor/etc/audio" 0 0 0755 0644 u:object_r:vendor_configs_file:s0
set_perm "$SRCDIR/system/lib64/libaudiopolicymanagerdefault.so" 0 0 0644 u:object_r:system_lib_file:s0
[ "$HAS_HAL" = 1 ] && set_perm "$SRCDIR/system/$HAL_REL" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$SRCDIR/system/bin/audioserver" 0 2000 0755 u:object_r:audioserver_exec:s0
