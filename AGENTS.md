# ksu-hires-unlocker

## 現況（2026-10-31）
- KernelSU 模組 Hi-Res Unlocker：讓系統混音器跟隨音檔取樣率（藍牙 A2DP、有線耳機、USB 音訊），每個裝置各打包一個 zip。
- GitHub：https://github.com/XPRAMT/ksu-hires-unlocker（公開）。
- 歷史：NX809J 的開發歷史（原 `D:\Android\ZTE\VoWiFI\ksu-hires-unlocker`，到 v0.8.0 + `tools/patch_audioserver.py`）與平板版歷史（原 `D:\Android\xaiomi\ksu-hires-unlocker-xaiomi`，路徑改寫到 `devices/liuqin/`）合併而成。歷史中已移除廠商檔（`original/`、`system/`）。A2DP sink 實驗（藍牙接收模式）沒有帶進來。

| 裝置 | 資料夾 | 模組 id | 版本 | 原廠備份 |
|---|---|---|---|---|
| RedMagic NX809J，Android 16（SDK 36） | `devices/nx809j` | `bt_hires_mixer` | v0.8.0（versionCode 11） | `/data/adb/bt_hires_mixer_stock/` |
| Xiaomi Pad 6 Pro liuqin，HyperOS 3 / Android 15（SDK 35） | `devices/liuqin` | `bt_hires_mixer_liuqin` | v0.8.0（versionCode 11，功能與 NX809J v0.8.0 相同，但沒有 HAL 補丁） | `/data/adb/bt_hires_mixer_liuqin_stock/` |

## 結構
- `common/lib.sh`：find_pat、patch_at、stock_sha（zip 內叫 `common.sh`）。
- `common/customize.sh`：安裝程式（裝置檢查、build_lib、備份與產生 XML、guard.conf、權限）。
- `common/post-fs-data.sh`：開機檢查；原廠檔改變就 skip_mount，否則設 `ro.audio.flinger_standbytime_ms`。
- `common/service.sh`：軟重啟自動重載。等覆蓋檔可見（cmp 模組副本與實際 XML、APM，最多 90 秒，不分掛載模組）與 sys.boot_completed；以 /proc/<pid>/maps 的 inode（不比 dev，overlay 的 dev 與 maps 不同）與 /proc/<pid>/exe 判斷行程是否仍用原廠檔；過期就 `setprop ctl.restart` HAL（若有）再 audioserver，每次開機一次（post-fs-data 寫 `.boot` token，service.sh 寫 `.reloaded`；軟重啟 boot_id 不變所以不用它）。紀錄 `$MODDIR/service.log`。device.sh 提供 RELOAD_HAL_SVC/RELOAD_HAL_BIN/RELOAD_HAL_LIB：NX809J `vendor.audio-hal-aidl`（/vendor/bin/hw/audiohalservice.qti，須映射 libaudiocorehal.qti.so）；liuqin 留空（legacy XML 由 audioserver 讀，HIDL HAL `vendor.audio-hal` = android.hardware.audio.service_64 沒有補丁），只檢查／重啟 audioserver。2026-11-01 實機唯讀驗證：NX809J 軟重啟後 HAL 與 audioserver 皆映射原廠檔（判為過期），liuqin 正常。尚未實機安裝測試。
- `devices/<裝置>/device.sh`：REQ_PROP/REQ_VAL/REQ_SDK、XML 路徑與備份檔名、補丁 pattern、HAS_HAL、AS_SKIP、`gen_xml`（設定檔格式不同，各自實作）。
- `devices/<裝置>/module.prop`、`devices/<裝置>/tools/*.py`（PC 端參考實作，會一起打包進 zip 的 `tools/`）。
- `build.py`（`build.ps1`、`build.sh` 只是包裝）→ `dist/bt_hires_mixer_<ZIP_MODEL>_<version>.zip`（ZIP_MODEL 寫在各 device.sh：nx809j → NX809J、liuqin → XiaomiPad6Pro；模組 id 不變）。zip 為扁平結構、LF、固定時間戳。
- `VERSION`、`RELEASE_NOTES.md`、`release.ps1` / `release.sh` → `tools/release.py`：發布流程（見「發布」）。
- `tools/selftest/`：在 Linux 上用假檔案跑安裝與開機檢查（不需要裝置）。

## 裝置差異
- NX809J：以 `ro.product.model=NX809J` 判斷；設定檔 `/vendor/etc/audio/sku_canoe/audio_module_config_primary.xml`（AIDL HAL 格式，port `deep_buffer_out`，sink `bt_a2dp_out` 等）；APM pattern `cmp w21,w8`；audioserver 24 bytes pattern，b.ge 在 +16；有 HAL 補丁（`libaudiocorehal.qti.so`，2 處）。
- liuqin：以 `ro.product.device=liuqin` 判斷；設定檔 `/vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml`（legacy 7.0 格式，port `deep_buffer`，sink `"BT A2DP Out"` 等，sources 可能在下一行）；APM pattern `cmp w22,w8`；audioserver 16 bytes 放寬 pattern，b.ge 在 +12；沒有 HAL 補丁（HIDL audio.primary.taro）。
- KernelSU 不分永久／臨時 root 都需要掛載用的 metamodule（例如 Hybrid Mount），且須實際掛載成功才會套用 `system/`（2026-11-01 NX809J 實證：Hybrid Mount 6.2.5 因舊版 config.toml 欄位解析失敗時，post-fs-data 有跑但覆蓋檔全沒套用）。liuqin 平板是 DFRoot 臨時 root，完整重開會掉 root。手動 bind mount 不可行（與 metamodule 重複，且 /data 為 nosuid 會讓 audioserver 起不來）。
- liuqin 尚未實測：taro HAL 能否開各取樣率的 deep_buffer、44.1/88.2k 是否爆音、各 PCM 格式是否被接受。

## 建置
- Windows：`.\build.ps1`（或 `.\build.ps1 liuqin`）；Linux：`./build.sh`。需要 Python 3。
- 自測：`tools/selftest/run.sh nx809j dist/bt_hires_mixer_NX809J_v0.8.0.zip`（需要 bash、awk、od、dd、unzip）。

## 發布
- 版本：根目錄 `VERSION`（X.Y.Z，所有裝置共用）。versionCode = X*10000 + Y*100 + Z（例：0.9.0 → 900），必須大於每台裝置目前的 versionCode。
- 標籤：`vX.Y.Z`，一個 release 附所有裝置的 zip（`bt_hires_mixer_<ZIP_MODEL>_vX.Y.Z.zip`）。不再使用 `nx809j-v…` / `liuqin-v…`。
- 流程：寫好 `RELEASE_NOTES.md`（繁中、英文兩節，不能留 TODO）→ `.\release.ps1 -DryRun` → `.\release.ps1`。腳本 `tools/release.py`：檢查 main、乾淨、與 origin 同步、標籤未用 → 寫入各 module.prop → build.py → 驗證 zip（必要檔案、版本、無廠商檔、無 CRLF）→ 產生 `dist/release-notes-vX.Y.Z.md` → commit「Release vX.Y.Z」→ tag → push → gh release create（Latest）。-DryRun 會還原 module.prop，不 commit、不 tag、不 push。
- 裝置從 `devices/*/`（有 device.sh 與 module.prop）自動找，新增裝置不用改腳本。
- 舊標籤（從 RedMagicX 轉來，名稱不變）：`hires-mixer-v0.7.0`（commit `38543d2`）、`hires-mixer-v0.8.0`（commit `ca388fd`，目前 Latest）。v0.8.0 的附件為 `bt_hires_mixer_NX809J_v0.8.0.zip` 與 `bt_hires_mixer_XiaomiPad6Pro_v0.8.0.zip`；v0.7.0 只有 NX809J；說明已註明臨時 root 需要 Hybrid Mount 這類掛載模組。
- RedMagicX 已沒有模組的 release 與檔案，README 只留連到本儲存庫的連結。

## 規則
- 版本只改 `VERSION`；module.prop 的 version、versionCode 由 release 流程寫入，installer 的版本字串由 module.prop 讀取。
- 不提交廠商檔或打包輸出（見 `.gitignore`）。
- 刷入與實機測試由使用者進行。
- README.md 與 README_TW.md 內容保持同步。
