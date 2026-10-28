"""Generate the overlay audio_module_config_primary.xml from the stock ROM file.

usage: python -I patch_config.py <stock.xml> <out.xml>
"""
import io
import re
import sys

BT_SINKS = ("bt_a2dp_out", "bt_a2dp_headphones", "bt_a2dp_speaker")
NEW_PORT = "deep_buffer_bt_hifi_out"
RATES = "44100 48000 88200 96000"
PCM_TYPES = ("INT_16_BIT", "FIXED_Q_8_24", "INT_24_BIT", "INT_32_BIT")

stock_path, out_path = sys.argv[1], sys.argv[2]
text = io.open(stock_path, encoding="utf-8", newline="").read()
assert "\r" not in text

# 1. add a DEEP_BUFFER mix port with 44.1-96 kHz profiles after deep_buffer_out
m = re.search(r'( *)<mixPort name="deep_buffer_out".*?</mixPort>\n', text, re.S)
assert m, "deep_buffer_out not found"
indent = m.group(1)
profiles = "".join(
    '%s    <profile samplingRates="%s" channelLayouts="LAYOUT_STEREO" formatType="PCM" pcmType="%s" />\n'
    % (indent, RATES, t)
    for t in PCM_TYPES
)
block = '%s<mixPort name="%s" role="source" flags="DEEP_BUFFER">\n%s%s</mixPort>\n' % (
    indent, NEW_PORT, profiles, indent)
text = text[:m.end()] + block + text[m.end():]

# 2. A2DP sinks use the new port instead of the 48 kHz deep_buffer_out
for sink in BT_SINKS:
    pattern = re.compile(r'(<route type="mix" sink="%s" sources=")([^"]*)(")' % sink)
    mm = pattern.search(text)
    assert mm, sink
    sources = mm.group(2).split(",")
    assert "deep_buffer_out" in sources, sink
    sources[sources.index("deep_buffer_out")] = NEW_PORT
    text = text[:mm.start(2)] + ",".join(sources) + text[mm.end(2):]

io.open(out_path, "w", encoding="utf-8", newline="").write(text)
print("ok")
