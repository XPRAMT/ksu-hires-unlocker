#!/system/bin/sh
# Installer: refuse to overlay a config that was not built from this stock file.
TARGET=/vendor/etc/audio/sku_canoe/audio_module_config_primary.xml
STOCK=8afbce6c280b731fb4d9aacc463f98db6be5f07c33489fb3f7a2e268645e30be
OURS=c347220963db9c934095bc03692040af3564ea050af5f3757ecb68285ba8fc1f

CUR=$(sha256sum "$TARGET" 2>/dev/null | cut -d' ' -f1)
if [ "$CUR" != "$STOCK" ] && [ "$CUR" != "$OURS" ]; then
  ui_print "! Stock audio_module_config_primary.xml differs from the one this module was built for."
  ui_print "! sha256: $CUR"
  abort "! Aborted: ROM version mismatch, module not installed."
fi

ui_print "- BT Hi-Res Mixer: adding deep_buffer_bt_hifi_out (44.1-96 kHz) for A2DP"
set_perm_recursive $MODPATH/system/vendor/etc/audio 0 0 0755 0644 u:object_r:vendor_configs_file:s0
