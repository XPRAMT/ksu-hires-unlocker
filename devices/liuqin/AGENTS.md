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
## 臨時 root（2026-10-31）
- 平板的 KernelSU 是開機後才注入的臨時 root：完整重開會掉 root，軟重啟只跑 post-fs-data（prop 會變成 500），不會掛載模組。
- 改用 mount_now.sh：檢查 guard SHA 後，在 init（pid 1）的 mount namespace 做 bind mount，只重啟 audioserver，失敗就全部還原。還原用 unmount_now.sh。
- 09:14 第一次直接從 /data/adb/modules bind：init 執行 audioserver 被 SELinux 拒絕（nosuid_transition、execute_no_trans，因為 /data 是 nosuid）。20 秒內沒有拉起，腳本自動還原，audioserver 已用原廠檔恢復。
- 修正：先把三個檔複製到 /dev/bt_hires_stage（suid tmpfs），再從那裡 bind。這個做法尚未在平板上執行驗證。