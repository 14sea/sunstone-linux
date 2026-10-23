# sunstone Linux 待辦

按優先順序。M5（Wi-Fi）走通後先回來處理「遺留問題」，再進 M6。現在在 M6（圖形桌面）。

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

## M6 遺留

- [ ] GPU 的 zap shader（a615_zap.*）是從本機舊的提取副本拷到手機的；`sunstone-fw-install` 應從手機自己的 super/vendor
      分區提取（lpextract + erofs），這樣才能重現。
- [ ] GPU 最高 650 MHz：速度檔 148 下游可到 700 MHz，但 gpucc 的頻率表沒有 700。
- [ ] boot-22（無 GPU 節點）有一次無日誌的啟動失敗，原因未明；netconsole 已就緒，再出現時能看到。
- [x] 真正的顯示驅動（MDSS/DPU/DSI + 面板，2026-10-23 屏幕正常）：面板驅動發完整的下游上電序列，DSC 切片高度 40。
- [ ] **面板驅動編進內核時開機卡死**（boot-34、45、57；記錄見 LOG.md boot-39–58）。現狀：boot_a 上是
      延遲 1 ms 的調試版（boot-58），正式方案未定（用户不要 workqueue 繞過）；`=m` 手動 insmod 也能用。
      - 觸發條件：msm 的綁定和第一次 modeset 在面板 probe 裏同步跑，且發生在內核初始化期間（`/init` 之前）。
        正常的做法（probe 末尾 `devm_mipi_dsi_attach`）正好就是這樣：DSI host 的 attach 觸發 component bind，
        bind 裏 `drm_client_setup` 做 fbdev 的第一次 modeset，modeset 給面板上電發命令。
      - 不出事的情況：同一時刻從 workqueue 做（boot-42，0.365 s）；initcall 結束後在 probe 裏同步做（boot-44，5 s
        unbind/bind；boot-38 insmod）；延遲 3 s / 20 s（boot-39/40）。
      - 出事的情況：fbcon 接管 msm 的 fb（正常配置，boot-34/45）→ 卡死；異步 probe（boot-57，PID 1 在 `/init`
        之前 `async_synchronize_full` 等它）→ 卡死；延遲接管（boot-53/55）→ 能開機但 DSI FIFO 錯誤
        （`dsi_err_worker: status=4`）、所有 DSI 命令超時 `-110`，面板沒初始化。
      - 拆開 bind 的幾步（msm 本地調試開關 `sunstone_keepfb`，boot-47/49/51）：只綁定不 modeset 正常；移除 simpledrm
        正常；建 fbdev 做 modeset 但 fbcon 不接管也能用，不過同樣有 FIFO 錯誤、上電序列慢到 1.3 s。
      - 已知：內核初始化期間的第一次 modeset 讓 DSI 出 FIFO 錯誤（`status=4` 是軟件匯總的 `DSI_ERR_STATE_FIFO`，
        不是寄存器原值；這條分支不做 `dsi_sw_reset()`，等於沒恢復），之後命令 DMA 超時。超時不能解釋卡死：
        `mipi_dsi_*_multi` 在第一次出錯後跳過其餘命令，每次 DMA 等 200 ms（boot-55 的 prepare 只用了 0.3 s），
        所以卡死另有原因（鎖等待、無界等待、中斷風暴或反覆重試）；`panic=20` 沒重啟也只說明沒有 panic。
      - workqueue 能用不等於「PID 1 必須往前走」：那時 probe 已經返回、設備鎖已釋放、驅動核心已完成綁定，
        這幾件事要分開測。boot-49 已經說明：保留標準的同步 attach、第一次 modeset 交給 userspace（phoc），正常。
      - 計劃（每次同一份 Image，只改一個條件）：
        (1) 用能開機但 DSI 出錯的配置（boot-55）拿證據：在 `dsi_fifo_status()` 清寄存器前把第一次異常存進內存
            （FIFO/INTR/STATUS/CLK/ACK/TIMEOUT 原值、當前命令和 DMA、DMA_DONE 計數、PID/comm/CPU/system_state、
            IRQ 狀態、時鐘 parent/rate、PLL lock、runtime PM 返回值），開機後讀出；IRQ 裏不直接大量打印。
            `Lucid PLL latch failed` 補上時鐘名、目標頻率、parent 頻率和調用棧（它只來自 dispcc 的
            disp_cc_pll0，和 DSI PHY PLL 是兩條路；失敗分支直接返回 -EINVAL，latch 位沒清）。
        (2) 正常配置加 `fb.lockless_register_fb=1`（只作診斷）：console_lock 是否參與卡死。
        (3) worker attach，同時讓 PID 1 在原位置做有超時的等待：成功是否真的需要 PID 1 往前走（另記 probe 和
            設備鎖的狀態）。不要在同步 probe 裏等後面的 initcall：同一個 PID 1 會自己死鎖；要測階段邊界，
            先讓 probe 返回，再由選定階段觸發 attach。
        另外確認 ABL 留下的 DSI/DPU 狀態（連續 splash 還在掃描）在第一次 modeset 時怎麼被接管。
      - 拿日誌的辦法：initcall 期間 netconsole 還沒起來（USB gadget 由 /init 配置），pstore 記錄衰減到不可讀，
        msm 接管後屏幕控制台不可見；可用 `sunstone_keepfb` 保留 simpledrm 控制台、`panic=0`、TER16x32 字體拍照。
      - 調試代碼（未提交，梳理後清理）：面板驅動的 `attach_delay_ms`/`attach_now` 參數和斷點日誌，
        `initramfs/init-m6` 的重新 probe 塊，msm_kms.c 的 `sunstone_keepfb`（只在 src 裏，不在補丁裏）。
- [ ] 面板 prepare 失敗後沒有恢復：Phosh 之後的 modeset 不會重新 prepare，屏幕一直黑。`m17_prepare()` 失敗時
      已經會復位、斷電；要查的是 DRM 的 active 狀態是否讓後續提交不再走完整的 disable/prepare/enable。先用一次
      完整的關閉再開啟顯示的提交驗證，不在 enable 裏補 prepare。
- [ ] 背光回調的 bug：`m17_bl_update_status`/`get_brightness` 清掉 `MIPI_DSI_MODE_LPM` 後，出錯直接返回，沒有恢復；
      應保存原 flags 並在所有出口恢復，處理和面板上下電的並發；面板沒上電時更新亮度只緩存不發 DSI，讀亮度也要處理。
      開機時 systemd-backlight 恢復亮度報 EINVAL（面板還沒上電）。gsd-power 的 `'max > min'` 斷言另查它讀的是哪個
      背光設備和數值，不先認定是同一個原因。
- [ ] `Lucid PLL latch failed. Output may be unstable!`：msm 綁定時每次出現兩次（dispcc 的 PLL 改頻率時）。
- [ ] pstore 不可用：開 ECC 後普通 reboot 能留下 console 記錄，但 DDR 在復位期間衰減嚴重（411 個塊無法糾正）；
      panic 走的是進 fastboot 的路徑，ABL 可能還會覆蓋。M1 時記錄基本完整（16 KB 約 10 處位翻轉）。ramoops 的
      ECC/dmesg 區目前只在 m6d 的 DTS 裏。
- [ ] lockdep 報告（調試內核，boot-53）：PSCI cpuidle 電源域 `genpd_add_subdomain` 裏 raw spinlock 下拿普通
      spinlock（Invalid wait context）；`qcom_scm_probe` → `qcom_tzmem_enable` → `qcom_scm_shm_bridge_enable`
      在原子上下文調用會睡眠的 SCM 調用。都像上游問題，和顯示無關。
- [ ] 休眠：現在用 `sleep.conf.d` 關掉了（gsd-power 會 s2idle，USB 和 Wi-Fi 都斷）。第一次休眠按電源鍵能恢復，
      第二次沒恢復。做電源管理時再查喚醒源和恢復路徑。
- [x] 內核源碼改由 git 管理（2026-10-23）：`tools/mk-kernel-tree.sh` 從 tarball + `kernel/patches/` 建出
      `src/linux-7.3`（tag `v7.3-tarball`，分支 `sunstone`，調試放在其上的分支，現在是 `debug/panel-early-bind`）；
      `build-kernel.sh` 不再打補丁，每次從 defconfig 重建 `.config`（`EXTRA_CONFIG=` 加調試片段），把源碼 commit、
      未提交改動和配置的哈希寫進 `out/build-STAGE.info`；`tools/export-kernel-patches.sh` 把 `sunstone` 寫回補丁。
      boot-58 的鏡像、Image、DTB 和手機上的 `/proc/config.gz` 存在 `out/saved/boot-58/`（源碼差異是按時間線重建的）。
- [ ] 熄屏/亮屏：Phosh 熄屏後 bl_power 4，再寫亮度報 EINVAL；按鍵喚醒沒反應。查 logind `HandlePowerKey=ignore`
      是否擋住了 Phosh 處理電源鍵，以及面板 disable/enable 之後能否重新亮起。
- [ ] 面板的 60 Hz 模式（下游 dfps 120/60）、亮度曲線（`bl-inverted-dbv`、最小亮度 4）、HBM/調光命令。
- [ ] phoc 打印「No panel found for compatibles」：gmobile 的面板數據庫裡沒有 sunstone（圓角/挖孔），可以給 gmobile 提交。
- [ ] DTS：`qcom,mdss-dsc-slice-height` 的坑記在面板驅動裡；m6e/m6f/m6g 二分樹在穩定後刪掉。
- [ ] Phosh 的 Wi-Fi 開關需要 NetworkManager（現在是 networkd + wpa_supplicant）。

## 以後

- [ ] **wlroots0.20 是本地補丁版**（0.20.2-1.1，`/etc/pacman.conf` 裡 IgnorePkg）：Arch 升級 wlroots0.20 或 phoc 換
      wlroots 版本時，用 `sunstone-build-wlroots-phosh` 重編，再解除 IgnorePkg。

- [ ] 熱管理：tsens 已有溫度，CPU 冷卻設備和電池溫度保護（充電器 JEITA）。
- [ ] PMK8350 ADC 通道、PM6125 溫度報警的閾值。
- [x] RTC 偏移：timesyncd 經 Wi-Fi 對時，`rtc-offset-save.path` 在對時後保存偏移（M5）。
- [ ] pacman 鏡像站換成就近的（現在重定向到美國，約 1.9 MB/s）；不再需要測試主機的 SOCKS 隧道。
- [ ] 內核模塊：現在所有驅動都編進內核，rootfs 裡沒有 `/lib/modules`；以後要裝模塊（`modules_install` + 推送）。
- [ ] 每個里程碑的 DTS 是串聯 include 的（m4 → m3 → m2）；穩定後合併成一個板級 `sm4375-xiaomi-sunstone.dts`。
