# Hi-Res Unlocker (KernelSU module)

[繁體中文](README_TW.md)

The stock Android mixer runs at 48 kHz, so every track is resampled to 48 kHz before it reaches Bluetooth, wired headphones or USB audio. This KernelSU module lets the mixer follow the sample rate of the file:

| Part | Change |
|---|---|
| Audio config (NX809J `audio_module_config_primary.xml`, liuqin `audio_policy_configuration.xml`) | One deep-buffer mix port per sample rate: 44.1 / 48 / 88.2 / 96 kHz on Bluetooth A2DP, and additionally 176.4 / 192 kHz on wired headphones and USB audio. |
| `libaudiopolicymanagerdefault.so` (2 bytes) | AOSP only compares the sample rate for requests above 48 kHz, so 44.1 / 48 kHz tracks land on whichever output opened first. The patch scores every request, so each track picks the port with its own rate. |
| `libaudiocorehal.qti.so` (2 sites, 32 bytes each; NX809J only) | The deep-buffer size is 40 ms of frames, which is 1764 / 3528 frames at 44.1 / 88.2 kHz, not a multiple of 16. AudioFlinger rounds up to 16 and splits every write in two, which crackles. The patch rounds the HAL size up to a multiple of 16. |
| `audioserver` (AudioFlinger, 1 instruction) + `ro.audio.flinger_standbytime_ms` | AudioFlinger keeps every output thread connected to Bluetooth in a standby wait of at least 3 s. While an old thread waits for standby, the output backend stays busy, so a stream with a different sample rate cannot start and the HAL drops its first writes (about 3 s of silence). The patch removes the 3 s floor (one branch instruction) and the module sets the standby delay to 500 ms at boot, for all output threads. |

No vendor file is shipped. The installer copies the device's own files, finds the patch sites by their instruction bytes (exact match count, otherwise it aborts), and generates the config from the device's own XML. At boot, if a stock file has changed (for example after an OTA), the module skips mounting and must be installed again.

## Supported devices

| Device | Folder | Module id | Version | Notes |
|---|---|---|---|---|
| RedMagic NX809J, Android 16 | `devices/nx809j` | `bt_hires_mixer` | v0.8.0 | Tested on RedMagicOS 11.0.22. See [NX809J measurements](#nx809j-measurements). |
| Xiaomi Pad 6 Pro (liuqin), HyperOS 3 / Android 15 | `devices/liuqin` | `bt_hires_mixer_liuqin` | v0.8.0 | No HAL patch (HIDL taro HAL). Not fully tested yet. |

The installer checks the device (`ro.product.model` / `ro.product.device`) and the Android version, and refuses anything else.

## Requirements

- KernelSU (or a compatible root manager running KernelSU modules).
- KernelSU always needs a mount metamodule such as Hybrid Mount (permanent and temporary root alike). The module only works when that metamodule actually mounts; otherwise the files under `system/` are not applied and only `post-fs-data.sh` runs.
- Troubleshooting: if hi-res doesn't work (e.g. USB/BT stuck at 48 kHz), first check the mount module's status page/logs. E.g. Hybrid Mount 6.2.5 mounts nothing if `/data/adb/hybrid-mount/config.toml` contains old-version fields (`enable_overlay_fallback`, `[kasumi]` tables): back it up, replace it with the module's bundled default config, then reboot. Quick check on NX809J: `grep -c deep_buffer_rate /vendor/etc/audio/sku_canoe/audio_module_config_primary.xml` should be > 0.

## Install

1. Download the zip for your device from [Releases](https://github.com/XPRAMT/ksu-hires-unlocker/releases) (one release `vX.Y.Z` holds the zip of every device), or build it yourself.
2. Install it in the KernelSU manager and reboot.
3. If there is no sound after a reboot, disable the module in the KernelSU manager (or boot into safe mode) and reboot again.

The NX809J releases v0.7.0 and v0.8.0 use the older tags `hires-mixer-v0.7.0` / `hires-mixer-v0.8.0` (asset `bt_hires_mixer_NX809J_vX.Y.Z.zip`).

### Backup of the stock config

The installer keeps a copy of the stock XML and uses it when you update the module while it is mounted:

- NX809J: `/data/adb/bt_hires_mixer_stock/audio_module_config_primary.xml`
- liuqin: `/data/adb/bt_hires_mixer_liuqin_stock/audio_policy_configuration.xml`

If the backup is missing, disable the module, reboot, and install again.

## NX809J measurements

Supports the RedMagic NX809J on Android 16: the installer checks the model and the Android version and refuses to install on anything else. It was developed and tested on RedMagicOS 11.0.22 (incremental `20260204.095106`); other builds of the same model are untested. The installer finds the patch sites by their instruction bytes and aborts if they are not found exactly as expected, and at boot the module disables itself if the system files it was built from have changed (for example after an OTA); install it again afterwards.

Comparison of the three outputs (measured on the phone):

| | Bluetooth (A2DP) | Wired 3.5 mm headphones | USB audio (DAC) |
|---|---|---|---|
| Sample rates the mixer follows | 44.1 / 48 / 88.2 / 96 kHz | 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz | 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz |
| Ports above 96 kHz | No (LDAC tops out at 96 kHz) | Yes | Yes |
| What sets the final output rate | The Bluetooth codec configuration: the LDAC DSP backend stays at 96 kHz on the tested phone | The PAL headphone device follows the stream rate | The PAL `USB_AUDIO-RX` backend follows the stream rate, limited to what the DAC supports (tested DAC: 32 to 384 kHz, 16 / 24 / 32 bit) |
| Sample-rate change at a song boundary | About 0.4 to 0.5 s of the new song is muted if the previous stream ended less than about 0.5 s earlier (about 2.7 s before v0.8.0); nothing is lost with a longer gap or at the same rate | Less than 0.3 s of the new song is muted (about 2 s before v0.8.0) | No delay seen (four back-to-back combinations, no start errors) |
| Standby delay | 500 ms (was 3 s) | 500 ms (was 2 s) | 500 ms (was 2 s) |
| 44.1 / 88.2 kHz crackle fix | Listening test clean | HAL write jitter (std) 18.7 ms to 2.0 ms at 44.1 kHz; listening clean | Jitter (std) 4.2 to 4.9 ms at every rate; listening clean |
| How it was checked | Mixer thread of each track, LDAC backend log, listening | Mixer thread, PAL device configuration, jitter statistics, listening | Mixer thread, PAL USB media configuration, jitter statistics, back-to-back playback, listening |
| Not verified | Codecs other than LDAC | The DAC clock itself | The DAC clock itself (ADSP offload hides it from ALSA); only one DAC tested |

Limits:

- The speaker and earpiece stay at 48 kHz (fixed hardware backend, smart amplifier).
- The Bluetooth and wired output backends run one sample rate at a time. If a different rate starts while the previous stream is still playing (cross-fade, preloading the next track), the new stream stays muted until the old one has finished plus the 0.5 s standby, because the HAL drops the writes while the start is retried.
- The 0.5 s standby is global. The Bluetooth output path holds about 0.35 to 0.44 s of audio, so the delay should not be set much lower (the end of a track could be cut). After a pause longer than 0.5 s playback starts about 0.1 s later (HAL restart), and short sounds on the speaker start about 30 to 50 ms later; nothing is lost. The change is made in `audioserver`; if you want to avoid it, use the [v0.7.0 release](https://github.com/XPRAMT/ksu-hires-unlocker/releases/tag/hires-mixer-v0.7.0) (everything except the standby change).
- Apps cannot ask for more than 192 kHz through `AudioTrack`; the 384 kHz `hifi_playback` output that exists on USB is unchanged.
- Only one USB DAC (Sony Audio) was tested.
- When 3.5 mm headphones and a USB DAC are connected together, Android plays through the 3.5 mm headphones.

The sample-rate gate in AOSP was reported upstream as [Issue Tracker 578577149](https://issuetracker.google.com/issues/578577149) with a work-in-progress change [4396965](https://android-review.googlesource.com/c/platform/frameworks/av/+/4396965).

## Build

Needs Python 3.

```powershell
.\build.ps1            # every device
.\build.ps1 liuqin     # one device
```

```sh
./build.sh
```

Output: `dist/bt_hires_mixer_<ZIP_MODEL>_<version>.zip`, for example `dist/bt_hires_mixer_NX809J_v0.8.0.zip`.

### Release

The version is in `VERSION` (X.Y.Z, shared by every device; versionCode = X*10000 + Y*100 + Z). Write `RELEASE_NOTES.md`, then:

```powershell
.\release.ps1 -DryRun   # build and verify only
.\release.ps1           # commit the version, tag vX.Y.Z, push, create the GitHub release with every zip
```

Smoke test on Linux, no device needed: `tools/selftest/run.sh nx809j dist/bt_hires_mixer_NX809J_v0.8.0.zip`.

## Layout

```
common/            installer, boot guard and shared helpers (same for every device)
devices/<device>/  device.sh (device check, paths, patch patterns, config generator), module.prop, tools/ (PC reference patchers)
tools/selftest/    fake-file test of a built zip
build.py           packs dist/bt_hires_mixer_<ZIP_MODEL>_<version>.zip (build.ps1 / build.sh wrap it)
```

Use at your own risk. This is an unofficial project, not affiliated with RedMagic, Nubia, ZTE, Xiaomi or Qualcomm.
