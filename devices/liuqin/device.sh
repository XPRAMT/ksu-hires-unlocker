# Device: Xiaomi Pad 6 Pro (liuqin), HyperOS 3 / Android 15. Sourced after common.sh by customize.sh
# and post-fs-data.sh. ro.product.device=liuqin (OTA metadata pre-device=liuqin), model 23046RP50C.
DEV_LABEL="Hi-Res Unlocker liuqin"
ZIP_MODEL=XiaomiPad6Pro       # zip name: bt_hires_mixer_<ZIP_MODEL>_<version>.zip
REQ_PROP=ro.product.device
REQ_VAL=liuqin
REQ_SDK=35          # Android 15 (HyperOS 3.0.7.0.VMYCNXM)
REQ_ANDROID=15
STOCKDIR_DEFAULT=/data/adb/bt_hires_mixer_liuqin_stock

# audio policy config loaded on this device (dumpsys media.audio_policy "Config source"; vendor sku cape)
XML=/vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml
XML_REL=vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml
XML_NAME=audio_policy_configuration.xml
XML_LABEL="audio policy config"
XML_ERR="deep_buffer or a Bluetooth/wired route not found"

# Instruction patterns (little-endian bytes).
# libaudiopolicymanagerdefault.so, AudioPolicyManager::selectOutput (liuqin: 0x44660):
#   stock   mov w8,#0xbb81 (48001) ; cmp w22,w8
#   patched mov w8,#1              ; cmp w22,w8
# (NX809J has cmp w21,w8.) The mov alone is unique as stock but "mov w8,#1" occurs 67 times, so the
# cmp is kept in the pattern to recognise an already patched file. tools/patch_apm_lib.py accepts
# any "cmp wN,w8" register.
APM_OLD_HEX=28709752df02086b
APM_NEW_HEX=28008052df02086b
APM_OLD_OCT='\050\160\227\122'
APM_NEW_OCT='\050\000\200\122'

# No HAL patch: this device uses the HIDL audio.primary.taro.so HAL (no libaudiocorehal).
HAS_HAL=0

# audioserver (AudioFlinger), PlaybackThread::cacheParameters_l(): connected to A2DP, the standby delay
# is raised to at least 3 s (kDefaultStandbyTimeInNsecs). Relaxed pattern (16 bytes, without the
# ldr/str of the member, whose offset differs per build: NX809J 0x2698, liuqin 0x2670):
#   mov w8,#0x5e00 ; movk w8,#0xb2d0,lsl#16 ; cmp x9,x8 ; b.ge +8
# The patch turns the b.ge (at +12) into an unconditional b +8, so the floor is never applied and the
# thread uses ro.audio.flinger_standbytime_ms (set below).
AS_OLD_HEX=08c08b52085ab6723f0108eb4a000054
AS_NEW_HEX=08c08b52085ab6723f0108eb02000014
AS_OLD_OCT='\112\000\000\124'
AS_NEW_OCT='\002\000\000\024'
AS_SKIP=12
STANDBY_MS=500      # ro.audio.flinger_standbytime_ms applied at boot

# service.sh soft-reboot reload: the legacy XML and the patched files are all used by audioserver, the
# HIDL HAL (vendor.audio-hal) has nothing patched, so only audioserver is checked and restarted.
RELOAD_HAL_SVC=

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
