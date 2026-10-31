# ksu-hires-unlocker

## 現況（2026-10-31）
- KernelSU 模組 Hi-Res Unlocker：讓系統混音器跟隨音檔取樣率（藍牙 A2DP、有線耳機、USB 音訊），每個裝置各打包一個 zip。
- GitHub：https://github.com/XPRAMT/ksu-hires-unlocker（公開）。
- 歷史：NX809J 的開發歷史（原 `D:\Android\ZTE\VoWiFI\ksu-hires-unlocker`，到 v0.8.0 + `tools/patch_audioserver.py`）與平板版歷史（原 `D:\Android\xaiomi\ksu-hires-unlocker-xaiomi`，路徑改寫到 `devices/liuqin/`）合併而成。歷史中已移除廠商檔（`original/`、`system/`）。A2DP sink 實驗（藍牙接收模式）沒有帶進來。

| 裝置 | 資料夾 | 模組 id | 版本 | 原廠備份 |
|---|---|---|---|---|
| RedMagic NX809J，Android 16（SDK 36） | `devices/nx809j` | `bt_hires_mixer` | v0.8.0（versionCode 11） | `/data/adb/bt_hires_mixer_stock/` |
| Xiaomi Pad 6 Pro liuqin，HyperOS 3 / Android 15（SDK 35） | `devices/liuqin` | `bt_hires_mixer_liuqin` | v0.1.0（versionCode 1） | `/data/adb/bt_hires_mixer_liuqin_stock/` |

## 結構
- `common/lib.sh`：find_pat、patch_at、stock_sha（zip 內叫 `common.sh`）。
- `common/customize.sh`：安裝程式（裝置檢查、build_lib、備份與產生 XML、guard.conf、權限）。
- `common/post-fs-data.sh`：開機檢查；原廠檔改變就 skip_mount，否則設 `ro.audio.flinger_standbytime_ms`。
- `devices/<裝置>/device.sh`：REQ_PROP/REQ_VAL/REQ_SDK、XML 路徑與備份檔名、補丁 pattern、HAS_HAL、AS_SKIP、`gen_xml`（設定檔格式不同，各自實作）。
- `devices/<裝置>/module.prop`、`devices/<裝置>/tools/*.py`（PC 端參考實作，會一起打包進 zip 的 `tools/`）。
- `build.py`（`build.ps1`、`build.sh` 只是包裝）→ `dist/<模組 id>-<version>.zip`。zip 為扁平結構、LF、固定時間戳。
- `tools/selftest/`：在 Linux 上用假檔案跑安裝與開機檢查（不需要裝置）。

## 裝置差異
- NX809J：以 `ro.product.model=NX809J` 判斷；設定檔 `/vendor/etc/audio/sku_canoe/audio_module_config_primary.xml`（AIDL HAL 格式，port `deep_buffer_out`，sink `bt_a2dp_out` 等）；APM pattern `cmp w21,w8`；audioserver 24 bytes pattern，b.ge 在 +16；有 HAL 補丁（`libaudiocorehal.qti.so`，2 處）。
- liuqin：以 `ro.product.device=liuqin` 判斷；設定檔 `/vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml`（legacy 7.0 格式，port `deep_buffer`，sink `"BT A2DP Out"` 等，sources 可能在下一行）；APM pattern `cmp w22,w8`；audioserver 16 bytes 放寬 pattern，b.ge 在 +12；沒有 HAL 補丁（HIDL audio.primary.taro）。
- liuqin 需要 KernelSU metamodule（例如 Hybrid Mount）才會掛載 `system/`；平板是 DFRoot 臨時 root，完整重開會掉 root。手動 bind mount 不可行（與 metamodule 重複，且 /data 為 nosuid 會讓 audioserver 起不來）。
- liuqin 尚未實測：taro HAL 能否開各取樣率的 deep_buffer、44.1/88.2k 是否爆音、各 PCM 格式是否被接受。

## 建置
- Windows：`.\build.ps1`（或 `.\build.ps1 liuqin`）；Linux：`./build.sh`。需要 Python 3。
- 自測：`tools/selftest/run.sh nx809j dist/bt_hires_mixer-v0.8.0.zip`（需要 bash、awk、od、dd、unzip）。

## 發布
- 標籤：`nx809j-vX.Y.Z`、`liuqin-vX.Y.Z`，每個 release 只附該裝置的 zip。
- 舊版 NX809J release（標籤 `hires-mixer-v0.8.0` 等，附件 `bt_hires_mixer_v0.8.0.zip`）留在 RedMagicX 儲存庫，不搬移。
- 本儲存庫尚未發布任何 release。

## 規則
- 改版時同步更新 `module.prop`（version、versionCode），installer 的版本字串由 module.prop 讀取。
- 不提交廠商檔或打包輸出（見 `.gitignore`）。
- 刷入與實機測試由使用者進行。
- README.md 與 README_TW.md 內容保持同步。
