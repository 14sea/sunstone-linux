# sunstone Linux 待辦

按優先順序。M5（Wi-Fi）走通後先回來處理「遺留問題」，再進 M6。

## 遺留問題（M4 結束時，2026-10-22）

- [ ] **modem 首次初始化卡住**（M5，boot-17/18）：`DOG detects stalled initialization` 約 65 s 後觸發，remoteproc
      自動重啟 modem 後正常，Wi-Fi 因此晚約 1 分鐘。內核 #17（boot-16）兩次啟動都沒有，#18 起兩次都有；兩者只差
      `CONFIG_EXTRA_FIRMWARE`（regdb），服務順序和 EFS 副本相同，可能只是巧合。做對照：#17 / 去掉 regdb 的 #18 各啟動幾次；
      卡住期間用 `qrtr-lookup` 看哪些 QMI 服務缺席；對比 tqftpserv 的請求（`ota_firewall/ruleset` 等 readwrite 文件缺失）。
- [ ] **CPU 空閒狀態**：`psci: failed to set PC mode: -3`、`CPUidle PSCI: failed to create CPU PM domains ret=-517`、
      `CPU 0 failed to PSCI idle`。sm6375.dtsi 用 OSI 模式的 PSCI 電源域；blair 的 PSCI 固件可能只支持 platform-coordinated
      模式，要對照下游 DT 的 idle states（`qcom,pm-cpu`、LPM 參數）改。影響待機功耗。
- [ ] **USB NCM 吞吐只有約 7 MB/s**（boot-6 的 `ssh dd`，兩端 CPU 空閒）：查 dwc3 的 TX FIFO、
      NCM 聚合參數（`ntb`）、SMMU 映射開銷，對比 iperf3。
- [ ] **充電控制**：bq25890 沿用 bootloader 的設置（輸入 500 mA、充電電流 512 mA）。要接 USB 類型檢測
      （BC1.2 / 快充頭），按下游的 3 A 充電電流和輸入限流配置；確認 SC89890H 和 BQ25890 不同的字段步進（ICHG 等）。
- [ ] **ModemManager 探測 ACM 串口**（測試主機）：init-m4/m5 已把 ACM 的 bInterfaceProtocol 設為 0，待驗證。
- [ ] **WLAN 板級數據**：QMI 報 board_id 0xff，ath10k 用的是 linux-firmware 的通用 board-2.bin；modem_a 裡有小米的
      `bdwlan.*`（82 個），要弄清下游按什麼選（芯片 OTP / 硬件版本），必要時做成 board-2.bin 或 board.bin。
- [ ] **每次重啟都進 fastboot**：shim 總是把 PON 原因設為 fastboot（調試用），離開測試主機就無法自己重啟回 Linux。
      shim 加一個不設 PON 原因的「正常」構建，或者在 Linux 裡清掉。

## 以後

- [ ] 熱管理：tsens 已有溫度，CPU 冷卻設備和電池溫度保護（充電器 JEITA）。
- [ ] PMK8350 ADC 通道、PM6125 溫度報警的閾值。
- [x] RTC 偏移：timesyncd 經 Wi-Fi 對時，`rtc-offset-save.path` 在對時後保存偏移（M5）。
- [ ] pacman 鏡像站換成就近的（現在重定向到美國，約 1.9 MB/s）；不再需要 測試主機的 SOCKS 隧道。
- [ ] 內核模塊：現在所有驅動都編進內核，rootfs 裡沒有 `/lib/modules`；以後要裝模塊（`modules_install` + 推送）。
- [ ] 每個里程碑的 DTS 是串聯 include 的（m4 → m3 → m2）；穩定後合併成一個板級 `sm4375-xiaomi-sunstone.dts`。
