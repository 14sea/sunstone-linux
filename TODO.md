# sunstone Linux 待辦

按優先順序。M5（Wi-Fi）走通後先回來處理「遺留問題」，再進 M6。

## 遺留問題（M4 結束時，2026-10-22）

- [ ] **modem 首次初始化卡住**（M5，boot-17/18）：`DOG detects stalled initialization` 約 65 s 後觸發，remoteproc
      自動重啟 modem 後正常，Wi-Fi 因此晚約 1 分鐘。內核 #17（boot-16）兩次啟動都沒有，#18 起兩次都有；兩者只差
      `CONFIG_EXTRA_FIRMWARE`（regdb），服務順序和 EFS 副本相同，可能只是巧合。
      2026-10-22 跟蹤（`sunstone-modem-trace`，`out/logs/modem-cycles/`）：#18 起 7 次冷啟動卡 5 次，手動 stop/start
      modem 也會卡 → 和開機時序無關。卡住期間 modem 只註冊了 43.18（SSCTL）和 66.180（servreg notifier），從沒聯繫
      rmtfs（rmtfs -v 的第一條是崩潰後的 bye），所以卡在讀 EFS 之前；正常時它接著向 PD mapper（64.1）查詢再讀 EFS。
      嫌疑：PD mapper 的應答或 sysmon/SSCTL 握手。下一步：卡住時抓 QRTR 報文（`qrtr` 沒有 dump 工具，用 tcpdump
      不行；可以在內核 qcom_pd_mapper 裡加 dev_dbg 看有沒有收到 locator 請求），或換用户態 pd-mapper 對比。做對照：#17 / 去掉 regdb 的 #18 各啟動幾次；
      卡住期間用 `qrtr-lookup` 看哪些 QMI 服務缺席；對比 tqftpserv 的請求（`ota_firewall/ruleset` 等 readwrite 文件缺失）。
- [x] **CPU 空閒狀態**（2026-10-22 查明，無需修改）：深度空閒正常，cpu0 開機約 170 s 裡有 155 s 在最深的
      rail power collapse，簇級空閒 S0 在 180 s 裡佔 153 s。三條報錯都是開機 0.2 s 內的一次性告警：PSCI 電源域第一次
      探測被推遲（-517），期間 cpu0 試了一次空閒失敗，0.22 s 以 OSI 模式初始化成功；`failed to set PC mode: -3` 是固件
      不允許切到 PC 模式。原記錄：`psci: failed to set PC mode: -3`、`CPUidle PSCI: failed to create CPU PM domains ret=-517`、
      `CPU 0 failed to PSCI idle`。sm6375.dtsi 用 OSI 模式的 PSCI 電源域；blair 的 PSCI 固件可能只支持 platform-coordinated
      模式，要對照下游 DT 的 idle states（`qcom,pm-cpu`、LPM 參數）改。影響待機功耗。
- [x] **USB NCM 吞吐**（2026-10-22 查明，無需修改）：iperf3（服務端在手機上；測試主機的防火牆擋入站）測得主機→手機
      283 Mbit/s，手機→主機 363 Mbit/s，已接近 USB 2.0 上限。當時的 7 MB/s 瓶頸在救援環境的 `gunzip | ssh(dropbear) | dd`
      管道，不在鏈路。原記錄：**USB NCM 吞吐只有約 7 MB/s**（boot-6 的 `ssh dd`，兩端 CPU 空閒）：查 dwc3 的 TX FIFO、
      NCM 聚合參數（`ntb`）、SMMU 映射開銷，對比 iperf3。
- [x] **充電控制**（boot-19 驗證：ICHG 1984 mA 按 BQ25890 表，SC89890H 實際約 1.86 A；CV 4.448 V，不超過 4.45 V；
      接電腦時輸入 500 mA）。快充頭下的輸入電流和溫度表現還沒實測。改動：去掉 read-back，DT 設 ICHG 2 A（SC89890H 上約 1.86 A）、CV 4.45 V（取整 4.432 V），
      預充/終止沿用 192/256 mA，輸入電流由芯片 BC1.2 檢測決定。原狀態：bq25890 沿用 bootloader 的設置（輸入 500 mA、充電電流 512 mA）。要接 USB 類型檢測
      （BC1.2 / 快充頭），按下游的 3 A 充電電流和輸入限流配置；確認 SC89890H 和 BQ25890 不同的字段步進（ICHG 等）。
- [x] **ModemManager 探測 ACM 串口**：ACM 的 bInterfaceProtocol 設為 0 後（boot-16 起），測試主機上的 ModemManager
      不再探測（16:20 之後 ttyACM0 出現 3 次都沒有探測記錄）。
- [ ] **WLAN 板級數據**：QMI 報 board_id 0xff，ath10k 匹配到 linux-firmware board-2.bin 的通用條目
      `bus=snoc,qmi-board-id=ff`（Chromebook 系列的數據）。modem_a 裡有 84 個 `bdwlan.*`（都是 26328 字節，約 40 組不同
      內容），沒有 board_id 0xff 對應的 `bdwlan.bin`；小米按自己的 SKU/地區選文件，規則要從小米開源的 sunstone 內核
      （icnss 的 BDF 文件名）查。在弄清之前不要隨便挑一個（發射功率表可能不對）。不要為了看日誌去啟動 crDroid：
      它可能格式化現在裝著 Arch 的 userdata。
      小米 sunstone-u-oss 內核（drivers/soc/qcom/icnss2）只對 WCN6750 下發 BDF；WCN3988 是 modem 上的 WLAN 固件自己
      經 TFTP 從 modem_a 讀。下一步：modem 重啟時 `strace -e openat -p <tqftpserv>` 看固件打開哪個 `bdwlan.*`，
      再把那個文件做成 ath10k 的 board.bin（或 board-2.bin 的 variant 條目）。
      結果：strace 下固件經 TFTP 只讀了 wlanmdsp.mbn 和 modem_pr 的配置，沒讀 bdwlan（ath10k 已經經 QMI 下發 BDF）。
      modem 讀的硬件配置是 `mcfg_hw/.../LA/CN/` 和 `cn_hw.txt`：國行硬件，板級數據多半也按地區選。
      `tools/mkboard2.py` 已備好（往 board-2.bin 加 `variant=xiaomi_sunstone` 條目，輸出到 /lib/firmware/updates）。
- [x] **每次重啟都進 fastboot**（boot-20 驗證）：shim 總是把 PON 原因設為 fastboot（調試用）。reboot-mode 原本不寫 0
      （補丁 0006）。現在：DTS 給 PM6125 PON 加
      `mode-normal = <0>`，普通 `reboot` 寫 0 回到 Linux，`reboot bootloader` 進 fastboot，panic 仍進 fastboot。
      刷機流程改用 `tools/remote/to-fastboot.sh`。

## 以後

- [ ] **wlroots0.20 是本地補丁版**（0.20.2-1.1，`/etc/pacman.conf` 裡 IgnorePkg）：Arch 升級 wlroots0.20 或 phoc 換
      wlroots 版本時，用 `sunstone-build-wlroots-phosh` 重編，再解除 IgnorePkg。

- [ ] 熱管理：tsens 已有溫度，CPU 冷卻設備和電池溫度保護（充電器 JEITA）。
- [ ] PMK8350 ADC 通道、PM6125 溫度報警的閾值。
- [x] RTC 偏移：timesyncd 經 Wi-Fi 對時，`rtc-offset-save.path` 在對時後保存偏移（M5）。
- [ ] pacman 鏡像站換成就近的（現在重定向到美國，約 1.9 MB/s）；不再需要 測試主機的 SOCKS 隧道。
- [ ] 內核模塊：現在所有驅動都編進內核，rootfs 裡沒有 `/lib/modules`；以後要裝模塊（`modules_install` + 推送）。
- [ ] 每個里程碑的 DTS 是串聯 include 的（m4 → m3 → m2）；穩定後合併成一個板級 `sm4375-xiaomi-sunstone.dts`。
