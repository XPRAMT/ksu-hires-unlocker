"""Patch the sample-rate gate in AudioPolicyManager::selectOutput (liuqin build).

The stock library compares the requested sampling rate with 48001 and skips the sampling-rate
criterion for every request <= 48000 Hz (AOSP: `if (samplingRate > SAMPLE_RATE_HZ_DEFAULT)`).
This changes `mov w8, #0xbb81` (48001) to `mov w8, #1`, so only an unspecified rate (0) skips the
criterion and every real request is scored (nearest rate >= request wins).

Relaxed search: `mov w8,#48001` followed by `cmp wN, w8` (any N; liuqin uses w22 at 0x44660,
NX809J w21), 4-byte aligned, exactly one match.

usage: python -I patch_apm_lib.py <stock.so> <out.so>
"""
import hashlib
import struct
import sys

STOCK_SHA256 = "36147e0a561ea246103860f372679b47b1ea4e3f72a89f5c1beedee1f9b4c9a3"  # OS3.0.7.0.VMYCNXM
OLD = bytes.fromhex("28709752")               # mov w8, #0xbb81  (48001)
NEW = bytes.fromhex("28008052")               # mov w8, #1

data = bytearray(open(sys.argv[1], "rb").read())
if hashlib.sha256(data).hexdigest() != STOCK_SHA256:
    print("warning: not the known stock library, relying on the pattern check")
sites = []
i = data.find(OLD)
while i >= 0:
    if i % 4 == 0:
        (cmp_insn,) = struct.unpack_from("<I", data, i + 4)
        if cmp_insn & 0xFFFFFC1F == 0x6B08001F:  # cmp wN, w8 (subs wzr, wN, w8)
            sites.append(i)
    i = data.find(OLD, i + 1)
assert len(sites) == 1, "expected exactly one patch site, found %d" % len(sites)
data[sites[0]:sites[0] + 4] = NEW
open(sys.argv[2], "wb").write(data)
print("patched mov at 0x%x; sha256 %s" % (sites[0], hashlib.sha256(data).hexdigest()))