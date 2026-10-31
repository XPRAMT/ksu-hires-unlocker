"""Fake stock files for tools/selftest/run.sh: random bytes with the stock patch patterns, and a
minimal audio config in the device format. Not real vendor files.

usage: python3 mkfix.py <device> <fake root>
"""
import os, sys, random
dev, R = sys.argv[1], sys.argv[2]
random.seed(1)
def blob(pats, n=8192):
    d = bytearray(random.getrandbits(8) for _ in range(n))
    for i, p in enumerate(pats):
        o = 1024 * (i + 1)
        d[o:o + len(p)] = p
    return bytes(d)
def w(p, b):
    p = R + p; os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "wb").write(b)
h = bytes.fromhex
if dev == "nx809j":
    w("/system/lib64/libaudiopolicymanagerdefault.so", blob([h("28709752bf02086b")]))
    hal = "08c9208be9f99ed2696abcf208f17dd3a974d3f28918e4f208fd43d3087dc99b00fd44d3"
    w("/vendor/lib64/hw/libaudiocorehal.qti.so", blob([h(hal), h(hal)]))
    w("/system/bin/audioserver", blob([h("694e53f908c08b52085ab6723f0108eb4a000054684e13f9")]))
    sinks = "bt_a2dp_out bt_a2dp_headphones bt_a2dp_speaker wired_headset wired_headphones usb_device_out usb_headset".split()
    x = ['<modules>', '    <mixPorts>',
         '        <mixPort name="primary_out" role="source" flags="PRIMARY">', '        </mixPort>',
         '        <mixPort name="deep_buffer_out" role="source" flags="DEEP_BUFFER">',
         '            <profile samplingRates="48000" channelLayouts="LAYOUT_STEREO" formatType="PCM" pcmType="INT_16_BIT" />',
         '        </mixPort>', '    </mixPorts>', '    <routes>']
    for s in sinks:
        x.append('        <route type="mix" sink="%s" sources="primary_out,deep_buffer_out" />' % s)
    x.append('        <route type="mix" sink="bt_a2dp_out" sources="deep_buffer_out" />')
    x += ['    </routes>', '</modules>']
    w("/vendor/etc/audio/sku_canoe/audio_module_config_primary.xml", ("\n".join(x) + "\n").encode())
else:
    w("/system/lib64/libaudiopolicymanagerdefault.so", blob([h("28709752df02086b")]))
    w("/system/bin/audioserver", blob([h("08c08b52085ab6723f0108eb4a000054")]))
    sinks = ["BT A2DP Out", "BT A2DP Headphones", "BT A2DP Speaker", "Wired Headset", "Wired Headphones", "USB Device Out", "USB Headset Out"]
    x = ['<audioPolicyConfiguration version="7.0">', '    <mixPorts>',
         '        <mixPort name="deep_buffer" role="source"', '                flags="AUDIO_OUTPUT_FLAG_DEEP_BUFFER">',
         '            <profile name="" format="AUDIO_FORMAT_PCM_16_BIT" samplingRates="48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>',
         '        </mixPort>', '    </mixPorts>', '    <routes>']
    for i, s in enumerate(sinks):
        if i == 2:
            x += ['        <route type="mix" sink="%s"' % s, '               sources="primary output,deep_buffer"/>']
        else:
            x.append('        <route type="mix" sink="%s" sources="primary output,deep_buffer"/>' % s)
    x += ['        <route type="mix" sink="BT A2DP Out" sources="a2dp output"/>', '    </routes>', '</audioPolicyConfiguration>']
    w("/vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml", ("\n".join(x) + "\n").encode())
