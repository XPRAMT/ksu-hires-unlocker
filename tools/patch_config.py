"""Generate the overlay audio_module_config_primary.xml from the stock ROM file.

usage: python -I patch_config.py <stock.xml> <out.xml>
"""
import io
import re
import sys

# sinks that get the per-rate deep-buffer ports instead of the 48 kHz deep_buffer_out
BT_SINKS = ("bt_a2dp_out", "bt_a2dp_headphones", "bt_a2dp_speaker")
WIRED_SINKS = ("wired_headset", "wired_headphones")   # v0.4.0: let the wired headphone path follow the file too
MIX_SINKS = BT_SINKS + WIRED_SINKS
# One DEEP_BUFFER port per rate. NOTE (verified on device, see AGENTS.md): AudioPolicyManager::
# selectOutput only compares sample rates for requests ABOVE 48000 Hz (nearest rate >= request wins);
# for requests <= 48000 Hz all outputs tie and the output opened first wins, and that open order is
# not controllable from this file. So 88.2k / 96k content follows the file, 44.1k / 48k content does not.
PORT_RATES = (
    ("deep_buffer_rate_48k_out", 48000),   # v0.2.1 experiment E1: 48k declared before 44k
    ("deep_buffer_rate_44k_out", 44100),
    ("deep_buffer_rate_88k_out", 88200),
    ("deep_buffer_rate_96k_out", 96000),
)
NEW_PORTS = [name for name, _ in PORT_RATES]
PCM_TYPES = ("INT_16_BIT", "FIXED_Q_8_24", "INT_24_BIT", "INT_32_BIT")

stock_path, out_path = sys.argv[1], sys.argv[2]
text = io.open(stock_path, encoding="utf-8", newline="").read()
assert "\r" not in text

# 1. add one DEEP_BUFFER mix port per rate after deep_buffer_out
m = re.search(r'( *)<mixPort name="deep_buffer_out".*?</mixPort>\n', text, re.S)
assert m, "deep_buffer_out not found"
indent = m.group(1)
block = ""
for name, rate in PORT_RATES:
    profiles = "".join(
        '%s    <profile samplingRates="%d" channelLayouts="LAYOUT_STEREO" formatType="PCM" pcmType="%s" />\n'
        % (indent, rate, t)
        for t in PCM_TYPES
    )
    block += '%s<mixPort name="%s" role="source" flags="DEEP_BUFFER">\n%s%s</mixPort>\n' % (
        indent, name, profiles, indent)
text = text[:m.end()] + block + text[m.end():]

# 2. Bluetooth A2DP and wired headphone sinks use the new ports instead of the 48 kHz deep_buffer_out
for sink in MIX_SINKS:
    pattern = re.compile(r'(<route type="mix" sink="%s" sources=")([^"]*)(")' % sink)
    mm = pattern.search(text)
    assert mm, sink
    sources = mm.group(2).split(",")
    assert "deep_buffer_out" in sources, sink
    i = sources.index("deep_buffer_out")
    sources[i:i + 1] = NEW_PORTS
    text = text[:mm.start(2)] + ",".join(sources) + text[mm.end(2):]

io.open(out_path, "w", encoding="utf-8", newline="").write(text)
print("ok")
