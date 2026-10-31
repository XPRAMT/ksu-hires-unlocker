"""Reference implementation of the audioserver patch that customize.sh applies on the tablet.

AudioFlinger raises the standby delay of every output thread connected to an A2DP device to at least
3 s (AOSP PlaybackThread::cacheParameters_l(), kDefaultStandbyTimeInNsecs). The patch turns the
floor's b.ge into an unconditional branch, so the thread uses ro.audio.flinger_standbytime_ms (the
module sets it to 500 at boot).

Relaxed pattern (16 bytes, exactly one match; the ldr/str member offset is not part of it:
NX809J 0x2698, liuqin 0x2670):
  mov w8,#0x5e00 ; movk w8,#0xb2d0,lsl#16 ; cmp x9,x8 ; b.ge +8
  08c08b52 085ab672 3f0108eb 4a000054  ->  ... 02000014   (b.ge -> b +8)
liuqin OS3.0.7.0.VMYCNXM: b.ge at 0x17e8a4.

usage: python -I patch_audioserver.py <in audioserver> <out audioserver>
"""
import hashlib
import sys

OLD = bytes.fromhex("08c08b52085ab6723f0108eb4a000054")
NEW = bytes.fromhex("08c08b52085ab6723f0108eb02000014")

data = bytearray(open(sys.argv[1], "rb").read())
sites = []
i = data.find(OLD)
while i >= 0:
    sites.append(i)
    i = data.find(OLD, i + 1)
assert len(sites) == 1, "expected exactly one patch site, found %d" % len(sites)
data[sites[0]:sites[0] + len(OLD)] = NEW
open(sys.argv[2], "wb").write(data)
print("patched the b.ge at 0x%x; sha256 %s" % (sites[0] + 12, hashlib.sha256(data).hexdigest()))