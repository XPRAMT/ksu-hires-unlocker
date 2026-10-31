# 高取樣率解鎖 Hi-Res Unlocker（KernelSU 模組）

[English](README.md)

原廠 Android 的系統混音固定 48 kHz，所有音軌都會先被重新取樣成 48 kHz，才送到藍牙、有線耳機或 USB 音訊。此 KernelSU 模組讓混音器跟隨音檔本身的取樣率：

| 項目 | 修改內容 |
|---|---|
| 音訊設定檔（NX809J 為 `audio_module_config_primary.xml`，liuqin 為 `audio_policy_configuration.xml`） | 每個取樣率一個 deep-buffer 混音埠：藍牙 A2DP 為 44.1 / 48 / 88.2 / 96 kHz，有線耳機與 USB 音訊另加 176.4 / 192 kHz。 |
| `libaudiopolicymanagerdefault.so`（2 bytes） | AOSP 只在請求高於 48 kHz 時比較取樣率，所以 44.1 / 48 kHz 音軌會落在最先開啟的輸出。補丁讓所有請求都參與評分，每個音軌都選到自己取樣率的埠。 |
| `libaudiocorehal.qti.so`（2 處，各 32 bytes；僅 NX809J） | deep-buffer 大小是 40 ms 的 frame 數，44.1 / 88.2 kHz 時為 1764 / 3528 frames，不是 16 的倍數。AudioFlinger 會進位到 16 的倍數，使每次寫入被拆成兩次而產生爆音。補丁把 HAL 的大小進位到 16 的倍數。 |
| `audioserver`（AudioFlinger，1 個指令）+ `ro.audio.flinger_standbytime_ms` | AudioFlinger 讓每條連接藍牙的輸出執行緒至少等待 3 秒才進入待機。舊執行緒等待待機期間，輸出後端仍被占用，不同取樣率的串流無法啟動，HAL 會丟棄開頭的寫入（約 3 秒靜音）。補丁拿掉這個 3 秒下限（一個分支指令），模組在開機時把所有輸出執行緒的待機延遲設為 500 ms。 |

zip 內不含任何廠商檔案。安裝程式複製裝置自己的檔案，依指令位元組找補丁位置（數量必須完全符合，否則中止安裝），並依裝置自己的 XML 產生設定。開機時若原廠檔案已改變（例如 OTA 後），模組會跳過掛載，需重新安裝。

## 支援裝置

| 裝置 | 資料夾 | 模組 id | 版本 | 備註 |
|---|---|---|---|---|
| RedMagic NX809J，Android 16 | `devices/nx809j` | `bt_hires_mixer` | v0.8.0 | 在 RedMagicOS 11.0.22 測試。見 [NX809J 實測](#nx809j-實測)。 |
| Xiaomi Pad 6 Pro（liuqin），HyperOS 3 / Android 15 | `devices/liuqin` | `bt_hires_mixer_liuqin` | v0.8.0 | 沒有 HAL 補丁（HIDL taro HAL）。尚未完整實測。 |

安裝程式會檢查裝置（`ro.product.model` / `ro.product.device`）與 Android 版本，不符就拒絕安裝。

## 需求

- KernelSU（或可執行 KernelSU 模組的 root 管理器）。
- 使用臨時 root 時（不分裝置），請安裝掛載用的 metamodule，例如 Hybrid Mount。沒有的話 `system/` 下的模組檔案不會被掛載，只會執行 `post-fs-data.sh`。

## 安裝

1. 從 [Releases](https://github.com/XPRAMT/ksu-hires-unlocker/releases) 下載自己裝置的 zip（每個 `vX.Y.Z` release 都附所有裝置的 zip），或自行編譯。
2. 在 KernelSU 管理器安裝後重新開機。
3. 若重開機後沒有聲音，在 KernelSU 管理器停用模組（或進入安全模式）再重開機。

NX809J 的 v0.7.0 與 v0.8.0 使用舊標籤 `hires-mixer-v0.7.0` / `hires-mixer-v0.8.0`（附件 `bt_hires_mixer_NX809J_vX.Y.Z.zip`）。

### 原廠設定備份

安裝程式會保存原廠 XML，模組已掛載時更新會使用這份備份：

- NX809J：`/data/adb/bt_hires_mixer_stock/audio_module_config_primary.xml`
- liuqin：`/data/adb/bt_hires_mixer_liuqin_stock/audio_policy_configuration.xml`

若沒有備份，請先停用模組、重開機，再重新安裝。

## NX809J 實測

支援 Android 16 的 RedMagic NX809J：安裝程式會檢查機型與 Android 版本，不符就拒絕安裝。開發與測試環境是 RedMagicOS 11.0.22（incremental `20260204.095106`），同機型的其他版本沒有測試。安裝程式依指令位元組找補丁位置，找不到預期結果就中止安裝；開機時若模組所依據的系統檔案已改變（例如 OTA 更新後），模組會自動停用，之後需重新安裝。

三種輸出的比較（手機上的實測）：

| | 藍牙（A2DP） | 3.5 mm 有線耳機 | USB 音訊（DAC） |
|---|---|---|---|
| 混音器跟隨的取樣率 | 44.1 / 48 / 88.2 / 96 kHz | 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz | 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz |
| 96 kHz 以上的埠 | 沒有（LDAC 最高 96 kHz） | 有 | 有 |
| 最終輸出取樣率由誰決定 | 藍牙編碼設定：測試機上 LDAC 的 DSP 後端維持 96 kHz | PAL 耳機裝置跟隨串流取樣率 | PAL 的 `USB_AUDIO-RX` 後端跟隨串流取樣率，受 DAC 支援範圍限制（測試的 DAC：32 到 384 kHz，16 / 24 / 32 位元） |
| 歌曲交界處更換取樣率 | 若前一個串流結束不到約 0.5 秒，新歌開頭約 0.4 到 0.5 秒會靜音（v0.8.0 之前約 2.7 秒）；間隔更長或取樣率相同則不會遺失 | 新歌開頭靜音不到 0.3 秒（v0.8.0 之前約 2 秒） | 沒有延遲（四種組合連續播放，無起播錯誤） |
| 待機延遲 | 500 ms（原 3 秒） | 500 ms（原 2 秒） | 500 ms（原 2 秒） |
| 44.1 / 88.2 kHz 爆音修復 | 聆聽測試無爆音 | 44.1 kHz 的 HAL 寫入抖動（標準差）18.7 ms 降到 2.0 ms；聆聽無爆音 | 各取樣率抖動（標準差）4.2 到 4.9 ms；聆聽無爆音 |
| 驗證方式 | 每個音軌的混音執行緒、LDAC 後端紀錄、聆聽 | 混音執行緒、PAL 裝置設定、抖動統計、聆聽 | 混音執行緒、PAL USB 媒體設定、抖動統計、連續播放、聆聽 |
| 尚未驗證 | LDAC 以外的編碼 | DAC 時脈本身 | DAC 時脈本身（ADSP 卸載讓 ALSA 看不到）；只測了一台 DAC |

限制：

- 喇叭與聽筒維持 48 kHz（固定的硬體後端與智慧功放）。
- 藍牙與有線的輸出後端一次只能跑一個取樣率。若前一個串流仍在播放時就啟動不同取樣率的串流（淡入淡出、預載下一首），新串流會靜音到舊串流播完再加 0.5 秒待機，因為重試啟動期間 HAL 會丟棄寫入。
- 0.5 秒待機是全域的。藍牙輸出路徑裡約排著 0.35 到 0.44 秒的音訊，所以延遲不宜再調低（曲尾可能被截）。暫停超過 0.5 秒後再播，開頭約晚 0.1 秒出聲（HAL 重啟）；喇叭上的短音效約晚 30 到 50 毫秒，都不會遺失。此變更是改 `audioserver`；若想避開，可使用 [v0.7.0 release](https://github.com/XPRAMT/ksu-hires-unlocker/releases/tag/hires-mixer-v0.7.0)（除了待機變更以外的全部功能）。
- App 透過 `AudioTrack` 最高只能要求 192 kHz；USB 上原本就有的 384 kHz `hifi_playback` 輸出沒有改動。
- 只測試了一台 USB DAC（Sony Audio）。
- 3.5 mm 耳機與 USB DAC 同時連接時，Android 會從 3.5 mm 耳機播放。

AOSP 的這個取樣率判斷已回報上游：[Issue Tracker 578577149](https://issuetracker.google.com/issues/578577149)，另有進行中的草稿變更 [4396965](https://android-review.googlesource.com/c/platform/frameworks/av/+/4396965)。

## 編譯

需要 Python 3。

```powershell
.\build.ps1            # 所有裝置
.\build.ps1 liuqin     # 單一裝置
```

```sh
./build.sh
```

輸出：`dist/bt_hires_mixer_<ZIP_MODEL>_<version>.zip`，例如 `dist/bt_hires_mixer_NX809J_v0.8.0.zip`。

### 發布

版本寫在 `VERSION`（X.Y.Z，所有裝置共用；versionCode = X*10000 + Y*100 + Z）。寫好 `RELEASE_NOTES.md` 後：

```powershell
.\release.ps1 -DryRun   # 只打包與驗證
.\release.ps1           # commit 版本、打 vX.Y.Z 標籤、push、建立附所有 zip 的 GitHub release
```

在 Linux 上不需裝置的自測：`tools/selftest/run.sh nx809j dist/bt_hires_mixer_NX809J_v0.8.0.zip`。

## 結構

```
common/            安裝程式、開機檢查與共用函式（所有裝置相同）
devices/<裝置>/    device.sh（裝置檢查、路徑、補丁 pattern、設定檔產生）、module.prop、tools/（PC 端參考補丁程式）
tools/selftest/    以假檔案測試打包好的 zip
build.py           打包 dist/bt_hires_mixer_<ZIP_MODEL>_<version>.zip（build.ps1 / build.sh 是包裝）
```

使用風險自負。本專案為非官方專案，與 RedMagic、Nubia、ZTE、Xiaomi、Qualcomm 無關。
