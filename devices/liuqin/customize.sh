#!/system/bin/sh
# Installer. Supported: Xiaomi Pad 6 Pro (liuqin) on Android 15. Nothing vendor-owned is shipped in
# this zip: the patched libraries and the mix-port config are built here from the tablet's own files.
# Patch sites are found by their instruction bytes and must match exactly once, otherwise the install
# aborts. Unlike the NX809J module there is no HAL patch (HIDL audio.primary.taro.so, no libaudiocorehal).
SRCDIR=${MODPATH:-${0%/*}}
. "$SRCDIR/common.sh"
: "${SRCXML:=$XML}"
: "${LIB:=/system/lib64/libaudiopolicymanagerdefault.so}"
: "${AS:=/system/bin/audioserver}"
: "${STOCKDIR:=/data/adb/bt_hires_mixer_liuqin_stock}"
: "${DEVICE:=$(getprop ro.product.device)}"
: "${SDK:=$(getprop ro.build.version.sdk)}"

[ "$DEVICE" = "$REQ_DEVICE" ] || abort "! Unsupported device '$DEVICE' (this module is for $REQ_DEVICE only)."
[ "$SDK" = "$REQ_SDK" ] || abort "! Unsupported Android version (SDK $SDK, need Android 15 = SDK $REQ_SDK)."

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

# gen_xml <stock xml> <out xml>: legacy audio_policy_configuration.xml (version 7.0). One DEEP_BUFFER
# mix port per sample rate, used by the Bluetooth A2DP sinks (44.1/48/88.2/96 kHz) and by the wired
# headphone and USB audio sinks (additionally 176.4/192 kHz). Same output as tools/patch_config.py.
gen_xml() {
  # pass 1: add the new mix ports after the stock deep_buffer port
  awk '
  BEGIN {
    n = split("deep_buffer_rate_48k_out deep_buffer_rate_44k_out deep_buffer_rate_88k_out deep_buffer_rate_96k_out deep_buffer_rate_176k_out deep_buffer_rate_192k_out", name, " ")
    split("48000 44100 88200 96000 176400 192000", rate, " ")
    split("AUDIO_FORMAT_PCM_16_BIT AUDIO_FORMAT_PCM_24_BIT_PACKED AUDIO_FORMAT_PCM_8_24_BIT AUDIO_FORMAT_PCM_32_BIT", fmt, " ")
  }
  {
    print
    if (!done && index($0, "<mixPort name=\"deep_buffer\"")) { match($0, /^ */); ind = substr($0, 1, RLENGTH); inport = 1 }
    if (inport && index($0, "</mixPort>")) {
      for (k = 1; k <= n; k++) {
        printf "%s<mixPort name=\"%s\" role=\"source\"\n%s        flags=\"AUDIO_OUTPUT_FLAG_DEEP_BUFFER\">\n", ind, name[k], ind
        for (j = 1; j <= 4; j++)
          printf "%s    <profile name=\"\" format=\"%s\"\n%s             samplingRates=\"%s\" channelMasks=\"AUDIO_CHANNEL_OUT_STEREO\"/>\n", ind, fmt[j], ind, rate[k]
        printf "%s</mixPort>\n", ind
      }
      inport = 0; done = 1
    }
  }
  END { if (!done) exit 3 }
  ' "$1" > "$2.tmp" || { rm -f "$2.tmp"; return 1; }
  # pass 2: in the primary module the sinks use the new ports instead of the 48 kHz deep_buffer
  # (first route of each sink whose sources contain deep_buffer; sources may be on the next line)
  awk '
  BEGIN {
    bt = "deep_buffer_rate_48k_out,deep_buffer_rate_44k_out,deep_buffer_rate_88k_out,deep_buffer_rate_96k_out"
    wd = bt ",deep_buffer_rate_176k_out,deep_buffer_rate_192k_out"
    nsink = split("BT A2DP Out|BT A2DP Headphones|BT A2DP Speaker|Wired Headset|Wired Headphones|USB Device Out|USB Headset Out", sink, "|")
    for (k = 1; k <= nsink; k++) want[sink[k]] = (k <= 3) ? bt : wd
  }
  function fix(line, nm,   s, src, n, a, i, out, v, found) {
    if (!match(line, /sources="[^"]*"/)) return line
    src = substr(line, RSTART + 9, RLENGTH - 10)
    n = split(src, a, ","); out = ""; found = 0
    for (i = 1; i <= n; i++) { v = a[i]; if (v == "deep_buffer") { v = want[nm]; found = 1 } out = out (i > 1 ? "," : "") v }
    if (!found) return line
    seen[nm] = 1
    return substr(line, 1, RSTART - 1) "sources=\"" out "\"" substr(line, RSTART + RLENGTH)
  }
  {
    if (pend != "") { $0 = fix($0, pend); pend = "" }
    else if (match($0, /<route type="mix" sink="[^"]*"/)) {
      nm = substr($0, RSTART + 24, RLENGTH - 25)
      if ((nm in want) && !(nm in seen)) {
        if (index($0, "sources=")) $0 = fix($0, nm); else pend = nm
      }
    }
    print
  }
  END { c = 0; for (k in seen) c++; if (c != nsink) exit 3 }
  ' "$2.tmp" > "$2"; rc=$?
  rm -f "$2.tmp"
  return $rc
}

GUARD="$SRCDIR/guard.conf"
: > "$GUARD"
ui_print "- Hi-Res Unlocker liuqin v0.1.0 ($DEVICE, Android 15)"

ui_print "  * audio policy library"
build_lib "$LIB" "$SRCDIR/system/lib64/libaudiopolicymanagerdefault.so" "$APM_OLD_HEX" "$APM_NEW_HEX" "$APM_OLD_OCT" "$APM_NEW_OCT" 0 1 APM

ui_print "  * audio server (A2DP standby floor)"
build_lib "$AS" "$SRCDIR/system/bin/audioserver" "$AS_OLD_HEX" "$AS_NEW_HEX" "$AS_OLD_OCT" "$AS_NEW_OCT" 12 1 AS

ui_print "  * audio policy config"
mkdir -p "$STOCKDIR"
if grep -q 'deep_buffer_rate_' "$SRCXML"; then               # this module's config is currently mounted
  [ -f "$STOCKDIR/audio_policy_configuration.xml" ] || abort "! Stock config backup missing: disable the module, reboot, then install again."
else
  cp "$SRCXML" "$STOCKDIR/audio_policy_configuration.xml" || abort "! Cannot back up $SRCXML"
fi
OUTXML="$SRCDIR/system/$XML_REL"
mkdir -p "${OUTXML%/*}"
gen_xml "$STOCKDIR/audio_policy_configuration.xml" "$OUTXML" || abort "! The audio config layout is not supported (deep_buffer or a Bluetooth/wired route not found)."
grep -q 'deep_buffer_rate_192k_out' "$OUTXML" || abort "! Generated config is incomplete."
echo "XML_STOCK_SHA=$(sha256sum "$STOCKDIR/audio_policy_configuration.xml" | cut -d' ' -f1)" >> "$GUARD"
echo "XML_OUT_SHA=$(sha256sum "$OUTXML" | cut -d' ' -f1)" >> "$GUARD"

ui_print "  * per-rate deep-buffer mix ports: 44.1/48/88.2/96 kHz for Bluetooth A2DP, plus 176.4/192 kHz for wired headphones and USB audio"
ui_print "  * audio policy: score the sampling rate for requests <= 48 kHz too"
ui_print "  * AudioFlinger: standby delay ${STANDBY_MS} ms (also on Bluetooth) so a new sample rate starts sooner"
set_perm_recursive "$SRCDIR/system/vendor/etc/audio" 0 0 0755 0644 u:object_r:vendor_configs_file:s0
set_perm "$SRCDIR/system/lib64/libaudiopolicymanagerdefault.so" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$SRCDIR/system/bin/audioserver" 0 2000 0755 u:object_r:audioserver_exec:s0