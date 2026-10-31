# Device: RedMagic NX809J, Android 16. Sourced after common.sh by customize.sh and post-fs-data.sh.
DEV_LABEL="Hi-Res Unlocker"   # installer banner: "- $DEV_LABEL <version> (<device>, Android <n>)"
REQ_PROP=ro.product.model     # property that identifies the device
REQ_VAL=NX809J
REQ_SDK=36                    # Android 16
REQ_ANDROID=16
STOCKDIR_DEFAULT=/data/adb/bt_hires_mixer_stock

# audio config overlaid by the module (audio_module_config_primary.xml, AIDL HAL format)
XML=/vendor/etc/audio/sku_canoe/audio_module_config_primary.xml
XML_REL=vendor/etc/audio/sku_canoe/audio_module_config_primary.xml
XML_NAME=audio_module_config_primary.xml   # name of the stock backup in $STOCKDIR
XML_LABEL="audio HAL config"
XML_ERR="deep_buffer_out or a Bluetooth/wired route not found"

# Instruction patterns (little-endian bytes).
# libaudiopolicymanagerdefault.so, AudioPolicyManager::selectOutput:
#   stock   mov w8,#0xbb81 (48001) ; cmp w21,w8
#   patched mov w8,#1              ; cmp w21,w8
APM_OLD_HEX=28709752bf02086b
APM_NEW_HEX=28008052bf02086b
APM_OLD_OCT='\050\160\227\122'
APM_NEW_OCT='\050\000\200\122'

# libaudiocorehal.qti.so, DeepBufferPlayback::getFrameCount: add x8,x8,w0,sxtw #2 followed by the
# 32 bytes below. The patch rounds the returned frame count up to a multiple of 16.
HAS_HAL=1
: "${HAL:=/vendor/lib64/hw/libaudiocorehal.qti.so}"
HAL_REL=vendor/lib64/hw/libaudiocorehal.qti.so
HAL_OLD_HEX=08c9208be9f99ed2696abcf208f17dd3a974d3f28918e4f208fd43d3087dc99b00fd44d3
HAL_NEW_HEX=08c9208ba9ef87d2a9c6abf21f2003d54937c9f28941e0f2084d1d91087dc99b00ed7c92
HAL_OLD_OCT='\351\371\236\322\151\152\274\362\010\361\175\323\251\164\323\362\211\030\344\362\010\375\103\323\010\175\311\233\000\375\104\323'
HAL_NEW_OCT='\251\357\207\322\251\306\253\362\037\040\003\325\111\067\311\362\211\101\340\362\010\115\035\221\010\175\311\233\000\355\174\222'
HAL_SKIP=4                    # bytes before the patched bytes in the pattern
HAL_COUNT=2                   # exact number of sites

# audioserver (AudioFlinger), PlaybackThread::cacheParameters_l(): connected to A2DP, the standby delay
# is raised to at least 3 s (kDefaultStandbyTimeInNsecs). Pattern (24 bytes):
#   ldr x9,[x19,#0x2698] ; mov w8,#0x5e00 ; movk w8,#0xb2d0,lsl#16 ; cmp x9,x8 ; b.ge +8 ; str x8,[x19,#0x2698]
# The patch turns the b.ge (at +16) into an unconditional b +8, so the floor is never applied and the
# thread uses ro.audio.flinger_standbytime_ms (set below).
AS_OLD_HEX=694e53f908c08b52085ab6723f0108eb4a000054684e13f9
AS_NEW_HEX=694e53f908c08b52085ab6723f0108eb02000014684e13f9
AS_OLD_OCT='\112\000\000\124'
AS_NEW_OCT='\002\000\000\024'
AS_SKIP=16
STANDBY_MS=500      # ro.audio.flinger_standbytime_ms applied at boot

# gen_xml <stock xml> <out xml>: one DEEP_BUFFER mix port per sample rate, used by the Bluetooth A2DP
# sinks (44.1/48/88.2/96 kHz) and by the wired headphone and USB audio sinks (additionally 176.4/192 kHz).
gen_xml() {
  # pass 1: add the new mix ports after the stock deep_buffer_out port
  awk '
  BEGIN {
    n = split("deep_buffer_rate_48k_out deep_buffer_rate_44k_out deep_buffer_rate_88k_out deep_buffer_rate_96k_out deep_buffer_rate_176k_out deep_buffer_rate_192k_out", name, " ")
    split("48000 44100 88200 96000 176400 192000", rate, " ")
    split("INT_16_BIT FIXED_Q_8_24 INT_24_BIT INT_32_BIT", type, " ")
  }
  {
    print
    if (!done && index($0, "<mixPort name=\"deep_buffer_out\"")) { match($0, /^ */); ind = substr($0, 1, RLENGTH); inport = 1 }
    if (inport && index($0, "</mixPort>")) {
      for (k = 1; k <= n; k++) {
        printf "%s<mixPort name=\"%s\" role=\"source\" flags=\"DEEP_BUFFER\">\n", ind, name[k]
        for (j = 1; j <= 4; j++)
          printf "%s    <profile samplingRates=\"%s\" channelLayouts=\"LAYOUT_STEREO\" formatType=\"PCM\" pcmType=\"%s\" />\n", ind, rate[k], type[j]
        printf "%s</mixPort>\n", ind
      }
      inport = 0; done = 1
    }
  }
  END { if (!done) exit 3 }
  ' "$1" > "$2.tmp" || { rm -f "$2.tmp"; return 1; }
  # pass 2: the five sinks use the new ports instead of the 48 kHz deep_buffer_out (first route of each sink)
  awk '
  BEGIN {
    bt = "deep_buffer_rate_48k_out,deep_buffer_rate_44k_out,deep_buffer_rate_88k_out,deep_buffer_rate_96k_out"
    wd = bt ",deep_buffer_rate_176k_out,deep_buffer_rate_192k_out"
    nsink = split("bt_a2dp_out bt_a2dp_headphones bt_a2dp_speaker wired_headset wired_headphones usb_device_out usb_headset", sink, " ")
    for (k = 1; k <= nsink; k++) want[sink[k]] = (k <= 3) ? bt : wd
  }
  {
    if (match($0, /<route type="mix" sink="[^"]*" sources="[^"]*"/)) {
      seg = substr($0, RSTART, RLENGTH)
      name = seg; sub(/^<route type="mix" sink="/, "", name); sub(/".*$/, "", name)
      if ((name in want) && !(name in seen)) {
        src = seg; sub(/^.* sources="/, "", src); sub(/"$/, "", src)
        n = split(src, a, ","); out = ""; found = 0
        for (i = 1; i <= n; i++) {
          v = a[i]; if (v == "deep_buffer_out") { v = want[name]; found = 1 }
          out = out (i > 1 ? "," : "") v
        }
        if (!found) bad = 1
        seen[name] = 1
        $0 = substr($0, 1, RSTART - 1) "<route type=\"mix\" sink=\"" name "\" sources=\"" out "\"" substr($0, RSTART + RLENGTH)
      }
    }
    print
  }
  END { c = 0; for (k in seen) c++; if (c != nsink || bad) exit 3 }
  ' "$2.tmp" > "$2"; rc=$?
  rm -f "$2.tmp"
  return $rc
}
