# sunstone Linux 構建和啟動記錄

| # | 日期 | 輸入 | 結果 | 日誌 |
| --- | --- | --- | --- | --- |
| 1 | 2026-10-22 | M1: shim SWEETLNX + Linux 7.3 (`0532be0`), minimal DTS, busybox `/init` (60 s, then `reboot -f`); `boot-m1.img` `0ca0a913e1f2e982` | **M1 通過**。shim 跳進 Linux；simpledrm 接管 splash（fb0、`/dev/dri/card0`），fbcon 135x150；`/init` 跑滿 60 s 後 `reboot -f`，手機回到 fastboot（刷完約 90 s）。看到單 CPU、GICv3 928 SPI、arch timer 19.2 MHz、MemTotal 7.2 GiB（三段 DDR 都在）。PSCI warm reset 保留了 DDR：console 和 pmsg 記錄完整讀出，但有零星位翻轉（16 KB 裡約 10 處，ramoops 沒開 ECC）。唯一告警：`psci: failed to set PC mode: -3`（無害） | `out/logs/boot-1/` |
