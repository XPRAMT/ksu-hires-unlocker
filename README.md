# Hi-Res Unlocker (KernelSU module)

[繁體中文](README_TW.md)

The stock Android mixer runs at 48 kHz, so every track is resampled to 48 kHz before it reaches Bluetooth, wired headphones or USB audio. This KernelSU module lets the mixer follow the sample rate of the file:

- **Audio config:** one deep-buffer mix port per sample rate. Bluetooth A2DP gets 44.1 / 48 / 88.2 / 96 kHz. Wired headphones and USB audio also get 176.4 / 192 kHz.
- **`libaudiopolicymanagerdefault.so`:** AOSP only compares sample rates for requests above 48 kHz, so 44.1 / 48 kHz tracks land on whichever output opened first. The patch scores every request, so each track picks the port with its own rate.
- **`audioserver` + `ro.audio.flinger_standbytime_ms=500`:** AudioFlinger keeps every Bluetooth output thread at least 3 s before standby, which mutes the start of a track with a different rate. The patch removes that floor and the module sets a 0.5 s standby.
- **`libaudiocorehal.qti.so` (NX809J only):** rounds the deep-buffer size up to a multiple of 16 frames (fixes 44.1 / 88.2 kHz crackle).

No vendor file is shipped. The installer copies the device's own files, finds the patch sites by their instruction bytes (exact match count, otherwise it aborts), and generates the config from the device's own XML. At boot, if a stock file has changed (for example after an OTA), the module skips mounting and must be installed again.

## Supported devices

| Device | Folder | Module id | Version | Notes |
|---|---|---|---|---|
| RedMagic NX809J, Android 16 | `devices/nx809j` | `bt_hires_mixer` | v0.8.0 | Tested on RedMagicOS 11.0.22. Measurements are in the [RedMagicX README](https://github.com/XPRAMT/RedMagicX#kernelsu-module-hi-res-unlocker). |
| Xiaomi Pad 6 Pro (liuqin), HyperOS 3 / Android 15 | `devices/liuqin` | `bt_hires_mixer_liuqin` | v0.1.0 | No HAL patch (HIDL taro HAL). Needs a KernelSU metamodule. Not fully tested yet. |

The installer checks the device (`ro.product.model` / `ro.product.device`) and the Android version, and refuses anything else.

## Requirements

- KernelSU (or a compatible root manager running KernelSU modules).
- **liuqin:** a KernelSU metamodule that mounts module files, such as Hybrid Mount. KernelSU v3+ no longer mounts `system/` itself; without a metamodule only `post-fs-data.sh` runs.

## Install

1. Download the zip for your device from Releases (tags `nx809j-vX.Y.Z` / `liuqin-vX.Y.Z`), or build it yourself.
2. Install it in the KernelSU manager and reboot.
3. If there is no sound after a reboot, disable the module in the KernelSU manager (or boot into safe mode) and reboot again.

Older NX809J releases (tag `hires-mixer-v0.8.0` and earlier) are in [RedMagicX Releases](https://github.com/XPRAMT/RedMagicX/releases).

### Backup of the stock config

The installer keeps a copy of the stock XML and uses it when you update the module while it is mounted:

- NX809J: `/data/adb/bt_hires_mixer_stock/audio_module_config_primary.xml`
- liuqin: `/data/adb/bt_hires_mixer_liuqin_stock/audio_policy_configuration.xml`

If the backup is missing, disable the module, reboot, and install again.

## Build

Needs Python 3.

```powershell
.\build.ps1            # every device
.\build.ps1 liuqin     # one device
```

```sh
./build.sh
```

Output: `dist/<module id>-<version>.zip`, for example `dist/bt_hires_mixer-v0.8.0.zip`.

Smoke test on Linux, no device needed: `tools/selftest/run.sh nx809j dist/bt_hires_mixer-v0.8.0.zip`.

## Layout

```
common/            installer, boot guard and shared helpers (same for every device)
devices/<device>/  device.sh (device check, paths, patch patterns, config generator), module.prop, tools/ (PC reference patchers)
tools/selftest/    fake-file test of a built zip
build.py           packs dist/<module id>-<version>.zip (build.ps1 / build.sh wrap it)
```

Use at your own risk. This is an unofficial project, not affiliated with RedMagic, Nubia, ZTE, Xiaomi or Qualcomm.
