# 高取樣率解鎖 Hi-Res Unlocker（KernelSU 模組）

[English](README.md)

原廠 Android 的系統混音固定 48 kHz，所有音軌都會先被重新取樣成 48 kHz，才送到藍牙、有線耳機或 USB 音訊。此 KernelSU 模組讓混音器跟隨音檔本身的取樣率：

- **音訊設定檔：** 每個取樣率一個 deep-buffer 混音埠。藍牙 A2DP 為 44.1 / 48 / 88.2 / 96 kHz，有線耳機與 USB 音訊另加 176.4 / 192 kHz。
- **`libaudiopolicymanagerdefault.so`：** AOSP 只在請求高於 48 kHz 時比較取樣率，44.1 / 48 kHz 音軌會落在最先開啟的輸出。補丁讓所有請求都參與評分，每個音軌都選到自己取樣率的埠。
- **`audioserver` + `ro.audio.flinger_standbytime_ms=500`：** AudioFlinger 讓連接藍牙的輸出執行緒至少等 3 秒才待機，造成換取樣率時新歌開頭靜音。補丁拿掉這個下限，模組把待機延遲設為 0.5 秒。
- **`libaudiocorehal.qti.so`（僅 NX809J）：** 把 deep-buffer 大小進位到 16 frames 的倍數（修正 44.1 / 88.2 kHz 爆音）。

zip 內不含任何廠商檔案。安裝程式複製裝置自己的檔案，依指令位元組找補丁位置（數量必須完全符合，否則中止安裝），並依裝置自己的 XML 產生設定。開機時若原廠檔案已改變（例如 OTA 後），模組會跳過掛載，需重新安裝。

## 支援裝置

| 裝置 | 資料夾 | 模組 id | 版本 | 備註 |
|---|---|---|---|---|
| RedMagic NX809J，Android 16 | `devices/nx809j` | `bt_hires_mixer` | v0.8.0 | 在 RedMagicOS 11.0.22 測試。實測數據見 [RedMagicX README](https://github.com/XPRAMT/RedMagicX/blob/main/README_TW.md)。 |
| Xiaomi Pad 6 Pro（liuqin），HyperOS 3 / Android 15 | `devices/liuqin` | `bt_hires_mixer_liuqin` | v0.1.0 | 沒有 HAL 補丁（HIDL taro HAL）。需要 KernelSU metamodule。尚未完整實測。 |

安裝程式會檢查裝置（`ro.product.model` / `ro.product.device`）與 Android 版本，不符就拒絕安裝。

## 需求

- KernelSU（或可執行 KernelSU 模組的 root 管理器）。
- **liuqin：** 需要會掛載模組檔案的 KernelSU metamodule，例如 Hybrid Mount。KernelSU v3 起不再自行掛載 `system/`；沒有 metamodule 時只會執行 `post-fs-data.sh`。

## 安裝

1. 從 Releases 下載對應裝置的 zip（標籤 `nx809j-vX.Y.Z` / `liuqin-vX.Y.Z`），或自行編譯。
2. 在 KernelSU 管理器安裝後重新開機。
3. 若重開機後沒有聲音，在 KernelSU 管理器停用模組（或進入安全模式）再重開機。

NX809J 的舊版（標籤 `hires-mixer-v0.8.0` 以前）在 [RedMagicX Releases](https://github.com/XPRAMT/RedMagicX/releases)。

### 原廠設定備份

安裝程式會保存原廠 XML，模組已掛載時更新會使用這份備份：

- NX809J：`/data/adb/bt_hires_mixer_stock/audio_module_config_primary.xml`
- liuqin：`/data/adb/bt_hires_mixer_liuqin_stock/audio_policy_configuration.xml`

若沒有備份，請先停用模組、重開機，再重新安裝。

## 編譯

需要 Python 3。

```powershell
.\build.ps1            # 所有裝置
.\build.ps1 liuqin     # 單一裝置
```

```sh
./build.sh
```

輸出：`dist/<模組 id>-<version>.zip`，例如 `dist/bt_hires_mixer-v0.8.0.zip`。

在 Linux 上不需裝置的自測：`tools/selftest/run.sh nx809j dist/bt_hires_mixer-v0.8.0.zip`。

## 結構

```
common/            安裝程式、開機檢查與共用函式（所有裝置相同）
devices/<裝置>/    device.sh（裝置檢查、路徑、補丁 pattern、設定檔產生）、module.prop、tools/（PC 端參考補丁程式）
tools/selftest/    以假檔案測試打包好的 zip
build.py           打包 dist/<模組 id>-<version>.zip（build.ps1 / build.sh 是包裝）
```

使用風險自負。本專案為非官方專案，與 RedMagic、Nubia、ZTE、Xiaomi、Qualcomm 無關。
