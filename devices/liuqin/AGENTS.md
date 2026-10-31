# ksu-hires-unlocker-xaiomi（平板版）

## 現況（2026-10-31）
- 從 D:\Android\ZTE\RedMagicX\ksu-hires-unlocker（NX809J v0.8.0）複製後改寫，原模組不得修改。
- 目標：Xiaomi Pad 6 Pro，ro.product.device=liuqin，model 23046RP50C，HyperOS OS3.0.7.0.VMYCNXM，Android 15（SDK 35），SM8475 taro。
- 模組 id：bt_hires_mixer_liuqin（與原模組 bt_hires_mixer 不衝突），v0.1.0。
- 設定檔：/vendor/etc/audio/sku_cape_qssi/audio_policy_configuration.xml（legacy 7.0 格式；dumpsys media.audio_policy 的 Config source）。
- 藍牙：兩台都是 A2DP offload，A2DP 掛在 primary 模組（"primary output"、"deep_buffer"），bluetooth_qti 模組的 "a2dp output" 是軟體備援。
- 修補：
  - APM 0x44660 mov w8,#48001 → mov w8,#1（後接 cmp w22,w8）。
  - audioserver 0x17e8a4 b.ge → b（成員 offset 0x2670）。
  - ro.audio.flinger_standbytime_ms=500。
- 沒有 HAL 修補：平板是 HIDL audio.primary.taro.so，沒有 libaudiocorehal。
- 原廠 SHA（從平板拉出的原檔，平板上只有 zygisk 模組）：
  - APM 36147e0a…
  - audioserver eebe949e…
  - xml 3d312a44…
- 安裝時在平板上產生檔案；原廠 xml 備份在 /data/adb/bt_hires_mixer_liuqin_stock。
- tools/*.py 是 PC 端參考實作，patch_config.py 的輸出與 customize.sh 的 gen_xml 逐位元組相同。

## 未驗證（需實測）
- taro HAL 能否開 44.1/88.2/96/176.4/192k 的 deep_buffer 輸出，並送到 A2DP offload 不重取樣。
- 44.1/88.2k 是否有 frame 對齊爆音。
- 新 port 的 PCM 格式（16、24 packed、8_24、32）HAL 是否都接受。

## 規則
- 打包輸出 *.zip 不進 git。
- 不在 PC 以外安裝；刷入與測試由使用者進行。
## 掛載（臨時 root）
- 需要 Hybrid Mount 這類 KernelSU metamodule（KernelSU v3+ 已移除內建掛載；沒有 metamodule 時只跑 post-fs-data 與 system.prop，不掛 system/vendor）。
- 平板是 DFRoot late-load 的臨時 root：完整重開會掉 root；裝好 metamodule 後軟重啟即會掛載（2026-10-31 以 Hybrid Mount 6.2.5 確認三檔為修補版）。
- 已排除：手動 bind mount 會與 metamodule overlay 重複；且來源在 /data（nosuid）會使 audioserver 無法啟動。
