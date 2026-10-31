"""Generate the overlay audio_policy_configuration.xml (legacy format 7.0) from the stock file.

Xiaomi Pad 6 Pro (liuqin) loads /vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml.
Reference implementation of gen_xml in customize.sh (both must give the same bytes).

usage: python -I patch_config.py <stock.xml> <out.xml>
"""
import io
import re
import sys
import xml.etree.ElementTree as ET

BT_SINKS = ("BT A2DP Out", "BT A2DP Headphones", "BT A2DP Speaker")
WIRED_SINKS = ("Wired Headset", "Wired Headphones", "USB Device Out", "USB Headset Out")
# One DEEP_BUFFER port per rate (see the NX809J module: the policy library is patched too, so every
# requested rate is scored and each track picks the port with its own rate).
PORT_RATES = (
    ("deep_buffer_rate_48k_out", 48000),
    ("deep_buffer_rate_44k_out", 44100),
    ("deep_buffer_rate_88k_out", 88200),
    ("deep_buffer_rate_96k_out", 96000),
    ("deep_buffer_rate_176k_out", 176400),   # wired / USB only
    ("deep_buffer_rate_192k_out", 192000),   # wired / USB only
)
WIRED_ONLY_PORTS = ("deep_buffer_rate_176k_out", "deep_buffer_rate_192k_out")
BT_PORTS = [n for n, _ in PORT_RATES if n not in WIRED_ONLY_PORTS]
WIRED_PORTS = [n for n, _ in PORT_RATES]
FORMATS = ("AUDIO_FORMAT_PCM_16_BIT", "AUDIO_FORMAT_PCM_24_BIT_PACKED",
           "AUDIO_FORMAT_PCM_8_24_BIT", "AUDIO_FORMAT_PCM_32_BIT")

stock_path, out_path = sys.argv[1], sys.argv[2]
text = io.open(stock_path, encoding="utf-8", newline="").read()
assert "\r" not in text

# 1. add one DEEP_BUFFER mix port per rate after the stock deep_buffer port
m = re.search(r'^( *)<mixPort name="deep_buffer".*?</mixPort>\n', text, re.S | re.M)
assert m, "deep_buffer not found"
ind = m.group(1)
block = ""
for name, rate in PORT_RATES:
    block += '%s<mixPort name="%s" role="source"\n%s        flags="AUDIO_OUTPUT_FLAG_DEEP_BUFFER">\n' % (ind, name, ind)
    for f in FORMATS:
        block += ('%s    <profile name="" format="%s"\n%s             samplingRates="%d" '
                  'channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>\n') % (ind, f, ind, rate)
    block += "%s</mixPort>\n" % ind
text = text[:m.end()] + block + text[m.end():]

# 2. first route of each sink whose sources contain deep_buffer (the primary module's route)
for sink in BT_SINKS + WIRED_SINKS:
    pat = re.compile(r'(<route type="mix" sink="%s"\s+sources=")([^"]*)(")' % re.escape(sink))
    for mm in pat.finditer(text):
        src = mm.group(2).split(",")
        if "deep_buffer" in src:
            i = src.index("deep_buffer")
            src[i:i + 1] = WIRED_PORTS if sink in WIRED_SINKS else BT_PORTS
            text = text[:mm.start(2)] + ",".join(src) + text[mm.end(2):]
            break
    else:
        raise AssertionError("no deep_buffer route for " + sink)

ET.fromstring(text.encode("utf-8"))            # must still be well-formed XML
io.open(out_path, "w", encoding="utf-8", newline="").write(text)
print("ok")