#!/system/bin/sh
# Installer: refuse to overlay files that were not built from this exact ROM build.
XML=/vendor/etc/audio/sku_canoe/audio_module_config_primary.xml
LIB=/system/lib64/libaudiopolicymanagerdefault.so
# known audio_module_config_primary.xml: stock and every released module version
X_STOCK=8afbce6c280b731fb4d9aacc463f98db6be5f07c33489fb3f7a2e268645e30be
X_V1=c347220963db9c934095bc03692040af3564ea050af5f3757ecb68285ba8fc1f
X_V2=03157e48ea2bfec50941ecd02b9fb86852942cde6e36cafc092230621763c311
X_V3=59364c812716987249fefb909c1b512ae94aae83675fda3524ec20e35cf7b85c
X_V4=ed34ecffe6ae02fb94406425e7948004e0954b5f61a3d81abe7aa9312d0d3e4b
# known libaudiopolicymanagerdefault.so: stock and patched
L_STOCK=d8a516c2c83ed712072f2f4cc5b85b7e7de10ba70e739c21909f3defd0ab7a93
L_PATCH=e4b9406b60187d6a6487e7a8f251b9a9bbf24eba54d2fadd8b4a52d08a3b29c8

CX=$(sha256sum "$XML" 2>/dev/null | cut -d' ' -f1)
CL=$(sha256sum "$LIB" 2>/dev/null | cut -d' ' -f1)
case "$CX" in
  "$X_STOCK"|"$X_V1"|"$X_V2"|"$X_V3"|"$X_V4") ;;
  *) ui_print "! audio_module_config_primary.xml differs from the one this module was built for ($CX)"
     abort "! Aborted: ROM version mismatch, module not installed." ;;
esac
case "$CL" in
  "$L_STOCK"|"$L_PATCH") ;;
  *) ui_print "! libaudiopolicymanagerdefault.so differs from the one this module was built for ($CL)"
     abort "! Aborted: ROM version mismatch, module not installed." ;;
esac

ui_print "- BT Hi-Res Mixer v0.4.0"
ui_print "  * per-rate deep-buffer mix ports (44.1/48/88.2/96 kHz) for Bluetooth A2DP and wired headphones"
ui_print "  * audio policy: score the sampling rate for requests <= 48 kHz too"
set_perm_recursive $MODPATH/system/vendor/etc/audio 0 0 0755 0644 u:object_r:vendor_configs_file:s0
set_perm $MODPATH/system/lib64/libaudiopolicymanagerdefault.so 0 0 0644 u:object_r:system_lib_file:s0
