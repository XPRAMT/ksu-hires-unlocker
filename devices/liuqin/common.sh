# Shared helpers (sourced by customize.sh and post-fs-data.sh).
# Xiaomi Pad 6 Pro: ro.product.device=liuqin (OTA metadata pre-device=liuqin), model 23046RP50C.
REQ_DEVICE=liuqin
REQ_SDK=35          # Android 15 (HyperOS 3.0.7.0.VMYCNXM)
# audio policy config loaded on this device (dumpsys media.audio_policy "Config source"; vendor sku cape)
XML=/vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml
XML_REL=vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml

# find_pat <file> <hex pattern> -> "<count> <byte offset> <byte offset> ..." (byte-aligned matches only)
find_pat() {
  od -An -v -tx1 "$1" | tr -d ' \n' | awk -v pat="$2" '
    { s = $0; p = 0
      while ((i = index(substr(s, p + 1), pat)) > 0) {
        pos = p + i
        if ((pos - 1) % 2 == 0) { n++; offs = offs " " (pos - 1) / 2 }
        p = pos
      } }
    END { print n + 0 offs }'
}

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
STANDBY_MS=500      # ro.audio.flinger_standbytime_ms applied at boot

# patch_at <file> <printf octal bytes> <offset> [<offset> ...]
patch_at() {
  f=$1; b=$2; shift 2
  for o in "$@"; do printf "$b" | dd of="$f" bs=1 seek="$o" conv=notrunc 2>/dev/null || return 1; done
}

# stock_sha <file> <old bytes (octal)> <offset> [<offset> ...]: SHA-256 of the file with every patch
# site reverted to the stock bytes, so it gives the same value whether the file is stock or patched.
stock_sha() {
  t="${TMPDIR:-/data/local/tmp}/.btm_norm.$$"
  f=$1; b=$2; shift 2
  cp "$f" "$t" && patch_at "$t" "$b" "$@" && sha256sum "$t" | cut -d' ' -f1
  rm -f "$t"
}