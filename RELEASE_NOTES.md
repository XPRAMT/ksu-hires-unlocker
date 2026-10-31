<!--
Release notes for the next release (tools/release.py reads this file).
Write both sections, then run .\release.ps1. Lines inside HTML comments are dropped.
The per-device zip list is added automatically. A release refuses to run while "TODO" is left in this file.
-->
## 繁體中文

- 新增軟重啟自動重載（`service.sh`）：KernelSU 軟重啟時若音訊 HAL／audioserver 比掛載模組早啟動而仍用原廠檔（卡在 48 kHz），開機完成後自動重啟一次；冷開機或掛載失敗時不做任何事。紀錄在模組資料夾的 `service.log`。

## English

- Soft-reboot auto-reload (`service.sh`): on a KernelSU soft reboot, if the audio HAL / audioserver started before the mount module and still use the stock files (stuck at 48 kHz), they are restarted once after boot. Nothing is done on a cold boot or when the mount failed. Log: `service.log` in the module folder.
