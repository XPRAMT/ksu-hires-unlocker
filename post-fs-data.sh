#!/system/bin/sh
# Safety guard: after a ROM update the stock file changes; then do not mount
# the outdated overlay (skip_mount), so audio keeps working with the new ROM.
MODDIR=${0%/*}
TARGET=/vendor/etc/audio/sku_canoe/audio_module_config_primary.xml
STOCK=8afbce6c280b731fb4d9aacc463f98db6be5f07c33489fb3f7a2e268645e30be
V1=c347220963db9c934095bc03692040af3564ea050af5f3757ecb68285ba8fc1f
V2=03157e48ea2bfec50941ecd02b9fb86852942cde6e36cafc092230621763c311

CUR=$(sha256sum "$TARGET" 2>/dev/null | cut -d' ' -f1)
if [ "$CUR" = "$STOCK" ] || [ "$CUR" = "$V1" ] || [ "$CUR" = "$V2" ]; then
  rm -f "$MODDIR/skip_mount"
else
  touch "$MODDIR/skip_mount"
fi
