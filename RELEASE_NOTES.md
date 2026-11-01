<!--
Release notes for the next release (tools/release.py reads this file).
Write both sections, then run .\release.ps1. Lines inside HTML comments are dropped.
The per-device zip list is added automatically. A release refuses to run while "TODO" is left in this file.
-->
## 繁體中文

- 新增軟重啟自動重載（`service.sh`）：KernelSU 軟重啟時，音訊 HAL／audioserver 可能比掛載模組早啟動而仍用原廠檔案（USB／藍牙卡在 48 kHz）。開機完成後會確認覆蓋檔已掛上，若音訊行程仍映射原廠檔案就自動重啟一次（每次開機最多一次；冷開機或掛載失敗時不做任何事）。紀錄在模組資料夾的 `service.log`。
  - NX809J：檢查並重啟 `vendor.audio-hal-aidl` 與 audioserver。2026-11-01 實機驗證：軟重啟後偵測到 HAL 仍用原廠檔，重啟後 reload ok，所有 `deep_buffer_rate_*` 輸出埠都已載入。
  - Xiaomi Pad 6 Pro：只檢查／重啟 audioserver（HAL 沒有補丁）；尚未在平板實機測試。
- 說明更新：KernelSU 不分永久或臨時 root，都需要可正常運作的掛載 metamodule（例如 Hybrid Mount）；掛載失敗時模組不會生效。新增疑難排解：Hybrid Mount 6.2.5 若 `config.toml` 含舊版欄位（`enable_overlay_fallback`、`[kasumi]`）會整個不掛載，請備份後換成模組附的預設設定檔再重新開機。

## English

- New soft-reboot auto-reload (`service.sh`): on a KernelSU soft reboot the audio HAL / audioserver may start before the mount module and keep the stock files (USB/Bluetooth stuck at 48 kHz). After boot it checks that the overlay is mounted and, if an audio process still maps the stock files, restarts it once (at most once per boot; nothing is done on a cold boot or when the mount failed). Log: `service.log` in the module folder.
  - NX809J: checks and restarts `vendor.audio-hal-aidl` and audioserver. Verified on the device on 2026-11-01: after a soft reboot the stale HAL was detected, reload ok, all `deep_buffer_rate_*` output ports loaded.
  - Xiaomi Pad 6 Pro: only audioserver is checked/restarted (no HAL patch); not yet tested on the tablet.
- Docs: KernelSU always needs a working mount metamodule such as Hybrid Mount (permanent and temporary root alike); the module has no effect if the mount fails. New troubleshooting: Hybrid Mount 6.2.5 mounts nothing if `config.toml` contains old-version fields (`enable_overlay_fallback`, `[kasumi]`); back it up, replace it with the module's bundled default config, then reboot.
