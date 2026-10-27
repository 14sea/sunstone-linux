# sunstone Linux 待辦

按優先順序。M5（Wi-Fi）走通後先回來處理「遺留問題」，再進 M6。現在（2026-10-26）：Ubuntu 上，外設見「還不能用的」
（音頻、傳感器、蜂窩數據、攝像頭已做），長期熄屏運行見「服務器」。

## 遺留問題（M4 結束時，2026-10-22）

- [x] **modem 首次初始化卡住**（2026-10-24 修好，補丁 0010，boot-102–106，見 LOG.md）：約一半的開機 modem 卡 65 s
      （`DOG detects stalled initialization`）、連崩 1–4 次，Wi-Fi 最晚 284 s。根因是 Linux 7.3 qrtr 的 HELLO 握手競態：
      我們的 HELLO 沒發出前 `qrtr_node_enqueue()` 丟掉其他控制包（-EAGAIN）；modem 的 HELLO 先到時，ns 回給它的本機服務通告
      （rmtfs、PD mapper、tqftpserv）被丟，`announce_servers()` 不重試，modem 等不到這些服務。修法：這時先當場發 HELLO
      再發包。驗證：modem stop/start 12/12、重啟 7/7 不卡，Wi-Fi 16–17 s。調試打印在 `kernel/debug/patches/qrtr-hello-order-log.patch`。
      可以考慮發上游（netdev），要先看最新主線是否已修。
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
- [x] **WLAN 板級數據**（2026-10-25，boot-114）：QMI 報 board_id 0xff，以前 ath10k 只匹配到 linux-firmware board-2.bin 的
      通用條目 `bus=snoc,qmi-board-id=ff`（Chromebook 系列的數據）。modem_a 裡 84 個 `bdwlan.*` 中有按機型和地區命名的
      `bdwlan.sunc/sung/suni`（sunstone 國行/國際/印度；`moong/mooni` 是 moonstone，和 sung/suni 相同）；默認的
      `bdwlan.bin` 就是 sunc。sunc 和 sung 差 340 字節（校驗和、功率表和地區限制所在的區段），sung 和 suni 差 4 字節。
      現在：DTS `qcom,calibration-variant = "xiaomi_sunstone"`，`sunstone-fw-install` 用 `bdwlan.sung`（用户選的，EU 使用；
      `WLAN_BDF=sunc` 換國行版）經 `sunstone-mkboard2` 生成 `/lib/firmware/updates/.../board-2.bin`，通用條目作為後備。
      近距離（-33 dBm）三者測不出差別：吞吐量 22/28–31 Mbit/s（受測試主機自己的 Wi-Fi 限制），無重傳；txpower 都報 20 dBm
      （驅動按地區規則的上限）。遠距離和邊緣信號的表現沒測。
- [x] **每次重啟都進 fastboot**（boot-20 驗證）：shim 總是把 PON 原因設為 fastboot（調試用）。reboot-mode 原本不寫 0
      （補丁 0006）。現在：DTS 給 PM6125 PON 加
      `mode-normal = <0>`，普通 `reboot` 寫 0 回到 Linux，`reboot bootloader` 進 fastboot，panic 仍進 fastboot。
      刷機流程改用 `tools/remote/to-fastboot.sh`。

## M6 遺留

- [x] GPU 的 zap shader（2026-10-25）：`sunstone-fw-install` 從手機自己的 vendor_a 提取（super 裏的 EROFS，`sunstone-lpmap`
      解析 LP 元數據找到偏移，只讀 loop + `mount -t erofs -o ro`，文件在 `/firmware/a615_zap.*`），和以前手動拷的逐字節相同。
      GPU 第一次使用時加載 SQE 和 zap，`eglinfo` 報 FD619 / OpenGL 4.6。開機時 msm 綁定（rootfs 還沒掛載）找不到 SQE，
      報一條錯誤，之後自己重試；把 SQE 編進內核反而多一條（接着找 zap，`gpu hw init failed`，boot-120），所以不編進去。
- [ ] GPU 最高 650 MHz：速度檔 148 下游可到 700 MHz，但 gpucc 的頻率表沒有 700。
- [ ] boot-22（無 GPU 節點）有一次無日誌的啟動失敗，原因未明；netconsole 已就緒，再出現時能看到。
- [x] 真正的顯示驅動（MDSS/DPU/DSI + 面板，2026-10-23 屏幕正常）：面板驅動發完整的下游上電序列，DSC 切片高度 40。
- [x] **面板驅動編進內核時開機卡死**（boot-34–81，記錄見 LOG.md）。根因：DTS 的 mdss 節點漏了
      `resets = <&dispcc DISP_CC_MDSS_CORE_BCR>`，msm 不復位 MDSS，ABL 的開機畫面要等 MDSS 斷一次電才停。面板 probe
      裏同步 attach 時（第一次 modeset 在 deferred probe 的 kworker 裏、probe 之內），驅動核心讓 DSI host 和 MDSS 保持
      活動，msm 把 SID 0x820 換到自己的 SMMU 域時 DPU 還在讀 0x85200000 → SMMU 上下文錯誤、DSI FIFO 下溢、硬卡死；PID 1
      在 `deferred_probe_initcall` 的 `flush_work` 上等它，所以 `/init` 不運行。workqueue/模塊/延遲能用，是因為 MDSS
      碰巧先 runtime suspend 斷了電。加上復位後正式版（主線寫法，`=y`）3/3 正常。/root/panel.ko 不再需要。
      調查用的工具：內核 git 樹的 `debug/panel-early-bind` 分支（導出在 `kernel/debug/patches/`），早期日誌通道
      （`kernel/debug/README.md`），`tools/run-exp.sh`。
- [ ] MDSS 復位之後，DSI PHY 註冊時鐘時報 `dsi0_phy_pll_out_dsiclk/byteclk already unprepared`（WARN）：dispcc 的
      byte0/pclk0 時鐘源帶 `CLK_OPS_PARENT_ENABLE`，孤兒重掛父時鐘時要先打開 PHY PLL，PHY 剛被復位還沒初始化，打開失敗
      但返回值被忽略，之後的關閉觸發告警。顯示正常。查 agatti（同樣的 dispcc 標誌 + 復位）上游有沒有處理；可能的修法：
      dispcc 在 PHY 時鐘可用前不要把這兩個 RCG 當成以 PHY 為父，或在 clk 框架裏讓 `__clk_set_parent_before` 失敗時不做
      對應的關閉。
- [ ] 面板 prepare 失敗後沒有恢復：Phosh 之後的 modeset 不會重新 prepare，屏幕一直黑。`m17_prepare()` 失敗時
      已經會復位、斷電；要查的是 DRM 的 active 狀態是否讓後續提交不再走完整的 disable/prepare/enable。先用一次
      完整的關閉再開啟顯示的提交驗證，不在 enable 裏補 prepare。
- [x] 背光回調的 bug（boot-87 修好）：鎖 + `prepared`，面板關着時只緩存，`mode_flags` 恢復原值；display-off 失敗不再
      讓 `panel->enabled` 留着。開機時 systemd-backlight 的 EINVAL 也隨之消失。gsd-power 的 `'max > min'` 斷言另查。
- [ ] `Lucid PLL latch failed`：每次開機兩次，都是 `dpu_kms_init` 經 OPP 設 MDP 時鐘時 dispcc 的 `disp_cc_pll0` 改頻
      （1120 MHz、747 MHz，parent 19.2 MHz，`PLL_MODE` 0x9000004/5）。失敗分支返回 -EINVAL 且沒清 latch 位；
      `dev_pm_opp_set_rate` 的失敗也沒人檢查，MDP 實際跑在什麼頻率要確認。對照下游 dispcc 的 PLL 配置
      （是否要求 PLL 在改頻時處於某種狀態，或 sm6375 的 Lucid 要用不同的 latch 流程）。
- [ ] `DSI PLL(0) lock failed, status=0x00000000` / `PLL(0) lock failed`：每次開機兩次（boot-133、134 都有，緊挨着 Lucid
      PLL 的兩條），顯示正常。可能是 MDSS 復位後 PHY 還沒初始化時就有人要 PLL（同上面的 byte/pclk 告警），一起查。
- [x] snap 掛載時 `SQUASHFS error: Xattrs in filesystem, these will be ignored`（兩個 snap，掛載正常）：`sunstone.config` 已加
      `SQUASHFS_XATTR=y`（Ubuntu 的內核也開）。（2026-10-26 boot-143：7 個 squashfs 掛載，沒有這條錯誤。）
- [x] **ADSP 重啟後整機復位**（boot-143；2026-10-26 修好，boot-152）：rx/tx/va macro 和 LPI 引腳控制器的時鐘來自 q6afe
      的時鐘控制器，它是 remoteproc 的子設備（ADSP 起來後才有），fw_devlink 只能把它們鏈到 remoteproc，而 remoteproc 在 ADSP
      重啟時不解綁：它們留着 clk_nodrv 的時鐘（−6/−ENXIO），聲卡重新綁定時無時鐘訪問寄存器，總線卡死。修法：
      本地補丁 0015（macro 和 LPI 探測時對真正的時鐘提供者建受管理的 device link → 時鐘控制器一走，驅動核心先解綁它們、
      連帶 SoundWire 和聲卡，發生在 remoteproc 斷電之前）；SoundWire 中斷在 DTS 改成上升沿（驅動申請的就是上升沿，
      LEVEL_HIGH 時第二次探測 `irq: type mismatch` → request_irq(0) 失敗）；`80-sunstone-lpass.rules` 在 q6afe 時鐘控制器
      綁定時經 systemd-run 跑 `sunstone-lpass-reprobe`（drivers_probe 這些設備；聲卡綁着卻沒有 card = 它的 DAI 名字指向
      已釋放的舊字符串（"CODEC DAI \x80\x16... not registered"），解綁再綁、20 s 內重試）；hexagonrpcd `Restart=always`
      （ADSP 重啟時它正常退出）。驗證：`echo stop/start` 和 debugfs `crash`（2，fatal error：remoteproc 的崩潰恢復）各數次，
      不再復位，聲卡約 2 s 回來，傳感器約 8 s，之後加速度計、光線、麥克風正常。恢復後揚聲器只響一聲很大的「啪」、
      沒有聲音（麥克風錄到峰值 16537、之後無音）：SoundWire 從設備重建後寄存器緩存是默認值，WCD 芯片卻保留着舊值，緩存
      跳過了要寫的寄存器 → 本地補丁 0016（wcd937x 組件 unbind 時硬件復位芯片）。boot-153 對照：重啓後 A、模擬崩潰後 B，
      三聲嘀都錄到（約 −36 dBFS），用户聽着一樣、無爆音。剩下：解綁時 `qcom_swrm_remove` 對已
      runtime suspend 的控制器 `clk_disable`（"already disabled" WARNING，主線 bug，無害）；沒試真的 DSP 崩潰。
- [x] **pstore**（2026-10-27，boot-177）：原來不可用：DDR 在復位期間衰減（`ramoops-peek` 看到 pmsg 區 900 KB 的圖案
      約 8% 的位翻轉，均勻分佈在每一頁，不是被覆蓋）。原因：TZ 沒有 PSCI SYSTEM_RESET2（SMC64/SMC32 的 PSCI_FEATURES
      都是 −1），Linux 只能用 SYSTEM_RESET，那是冷復位，PM6125 PON 的 PS_HOLD 類型（0x85a，ABL 開機時設成 0x07 硬復位）
      寫成熱復位也沒用。修法：① DTS `syscon-reboot`（優先級 192，先於 PSCI 的 129）寫 0 到 MPM PS_HOLD（0x440b000，下游的
      `qcom,pshold`），PMIC 按 PS_HOLD 類型復位，1 s 後還活着就回落到 PSCI；② 本地補丁 0029：`pm8941-pwrkey` 在 probe 時就按
      `reboot=warm` 設熱復位（原來只在 reboot notifier 裏設，panic 的 emergency restart 不走 notifier）。驗證：模塊實驗
      （熱類型 + 拉 PS_HOLD）後 900 KB 圖案只差頭部 6 個字節；boot-177 上普通 reboot、sysrq panic、全部 CPU 關中斷卡死
      （看門狗 bite，TZ 復位）三種都留下記錄（console 最後一行就是復位前那條）。ramoops 佈局改成 console 1 MB + 6 個
      128 KB 的 dmesg 記錄（oops/panic）+ pmsg 256 KB，沒開 ECC（熱復位後 0 位翻轉）。之前「pstore 是空的」還有一半是
      systemd-pstore：它把記錄搬到 /var/lib/systemd/pstore 並刪掉 pstore 裡的；每次開機用同樣的文件名覆蓋 →
      `sunstone-pstore-keep.service` 把每次的記錄放進 `/var/lib/systemd/pstore/<UTC 時間>/`，保留最新 30 份。
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
- [x] 熄屏/亮屏（boot-87 確認）：電源鍵由 Phosh 處理（它和 gsd-media-keys 持有 `handle-power-key` 抑制器，logind 的
      `HandlePowerKey=ignore` 不影響），按一下滅、按一下亮，空閒後自動熄屏也正常。以前「按鍵沒反應」是面板關閉後
      無法重新點亮（display-off 失敗留下 enabled、關屏時寫亮度 EINVAL），boot-87 修好了。
- [x] 面板的 60 Hz 模式（2026-10-25，boot-131/133，補丁 0008）：下游 `qcom,dsi-supported-dfps-list = <120 60>`、
      `dfps_immediate_porch_mode_vfp`：像素時鐘不變，60 Hz 只加長垂直前肩（20 → 2452 行）；DDIC 的幀率寄存器 60 01（120 Hz）
      / 60 21（60 Hz），即下游的 bc-120hz/-60hz 命令，上電序列按 connector 狀態裡的模式選（同 panel-novatek-nt35950）。
      120 Hz 仍是首選。用户：60 Hz 畫面正常，但沒有 120 Hz 絲滑，所以 GNOME 默認保持 120 Hz（「顯示器」裡可以切）；
      GNOME 空閒時 gnome-shell CPU 120 Hz 37、60 Hz 14 ticks/10 s。
- [ ] 面板的亮度曲線（`bl-inverted-dbv`、最小亮度 4）、HBM/調光命令。
      用户反饋（boot-87）：亮度 80 和 300 看起來差不多（讀回值正確）。查三星 `bl-dcs-type-ss-ea` 和
      `bl-inverted-dbv` 在下游 dsi_panel.c 裏怎麼換算 51h 的兩個字節（字節序、是否取反），再看整個 4–2047 範圍的實際效果。
- [x] phoc 打印「No panel found for compatibles」：gmobile 的面板數據庫裡沒有 sunstone（圓角/挖孔），可以給 gmobile 提交。（2026-10-25 關閉：只關 Arch，Arch 已不在手機上，備份可以刷回）
- [x] DTS：`qcom,mdss-dsc-slice-height` 的坑記在面板驅動裡；m6e/m6f/m6g 二分樹已刪（2026-10-25，見下面的 DTS 合併）。
- [x] Phosh 的 Wi-Fi 開關需要 NetworkManager（現在是 networkd + wpa_supplicant）。（2026-10-25 關閉：只關 Arch，Arch 已不在手機上，備份可以刷回）；Ubuntu 上可選 NetworkManager（`wifi-to-networkmanager.sh`）。

## 服務器（長期熄屏運行，2026-10-23 起的目標）

- [x] 充電上限：恆壓 4.1 V（約 80 %，m5 的 `&charger`），運行時可寫 `constant_charge_voltage` 臨時充滿。
- [x] panic 後自動回 Linux：shim 默認不設 fastboot 原因（`PON_FASTBOOT=1` 構建恢復開發用的安全網）。
- [x] 默認文本模式（`multi-user.target`），Phosh 保留；控制台 `consoleblank=120` 自動關面板。
- [x] 硬件看門狗（boot-93/95）：APSS WDT，`qcom-wdt`，systemd `RuntimeWatchdogSec=30s`；bite 後自動回 Linux。
      開機階段（2026-10-25，boot-108–113）：shim 跳進 Linux 前啟動看門狗（32 s，`SHIM_WDT`，mkboot.sh 只在 Image 帶 qcom-wdt
      時打開），qcom-wdt probe 時接手，看門狗核心代餵到 systemd 打開為止，最多 `watchdog.open_timeout=120` s。驗證：PID 1 卡在
      shell（`rdinit=/bin/sh`，open_timeout 20）→ 每次約 53 s 復位，7 次後停在 fastboot（374 s，tries 0）；不加載驅動
      （`initcall_blacklist`）→ 每次約 55 s 復位，386 s 後 fastboot。正常開機不受影響（>160 s 無復位）。
- [x] 過熱保護（boot-97/99）：CPU/GPU 溫區的 `cooling-maps` + 250 ms 被動輪詢，模擬驗證逐檔降頻。
      `cpu-unk0/1` 2026-10-27 綁到 A78（見「以後」的熱管理）；電池溫區（sm5602）沒有觸發點，充電靠充電器的 JEITA（TS 腳）；
      真實高負載下的溫度曲線放到長時間測試裏看。
- [x] 長時間穩定性測試（boot-99，24 h 通過，見 LOG.md）：內存、溫度、Wi-Fi、內核錯誤、電池在 4.0–4.1 V 之間。
- [x] 最終配置上再跑 24 h（modem 修復、電源鍵、啟動成功標記、省電關、開機看門狗），期間故意觸發看門狗復位和 panic。
      （2026-10-25 併入下面「Ubuntu 上跑一次 24 h 穩定性測試」；故意的 panic、看門狗、活鎖測試已在 boot-108–113 做過。）
- [x] 文本模式下電源鍵熄屏/亮屏（2026-10-25，用户按鍵確認：亮、滅、亮）：`sunstone-powerkey.service` 監聽 pm8941_pwrkey，
      控制台是文本模式時用 `TIOCLINUX` 切換（BLANKEDSCREEN 查狀態，BLANKSCREEN/UNBLANKSCREEN）；圖形模式（Phosh）時不管。
      `consoleblank` 的自動熄屏被改成強制熄屏，所以只有電源鍵能點亮，其他按鍵和內核消息不會。
- [x] 健康日誌的 `kerr` 改從 journal 數本次開機的內核錯誤（環形緩衝區會被擠掉）；root 開 linger
      （`/var/lib/systemd/linger/root`）：以前每次 ssh 都重新拉起 user@0（約 0.8 s），還打一條 `pam_warn(systemd-user:setcred)`
      （`/usr/lib/pam.d/systemd-user` 沒有 auth 段，setcred 落到 `other`），測試主機每分鐘探測一次就刷滿了 dmesg。
- [x] **連續重啟 7 次後停在 fastboot**（2026-10-25 發現並修好）：ABL 每次開機把 boot_a 的重試次數（GPT 屬性 bit 51–53）
      減 1，系統沒有把 slot 標成啟動成功（bit 54，Android 的 boot control 做這件事）；刷機時的 `fastboot set_active a`
      會重置次數，所以以前沒暴露。boot-106 之後 6 次測試重啟 + 1 次就用完了，`slot-unbootable:a: yes`。用户同意後：
      `sunstone-boot-success`（開機 2 min 後的 timer）只改 sde 上 boot_a 條目的 bit 54 和兩份 GPT 的 CRC，寫前校驗並備份、
      寫後讀回比對（9 個字節/份，和預期一致）；之後連續重啟兩次，tries 一直是 6。看門狗復位、panic 也不再消耗次數。
      已確認（2026-10-25）：`fastboot set_active a`（刷機流程的一步）把 successful 清成 no、tries 重置為 7；開機後 ABL 減到 6，
      2 min 後服務標上 successful。所以新內核照樣有 7 次機會。
- [x] Wi-Fi 省電關掉（2026-10-25）：udev 規則在 wlan0 出現時 `iw dev wlan0 set power_save off`（重啟後確認生效）。
      測試主機到手機的 ping 從平均 68.6 ms（最大 137）降到 4.9 ms（最大 7.9）。
- [x] Wi-Fi 斷線重連（2026-10-25，`tools/wifi-ap-test.py` + `tools/esp8266-ap`，ESP8266 當測試 AP）：AP 消失 10 s / 60 s / 300 s
      後重新出現，手機分別 4 / 7 / 13 s 後重新連上並 ping 通 AP，無需干預；回到原網絡後 DHCP 拿回原地址。開機時 modem 卡 65 s
      的問題已修（見上，補丁 0010）。
- [x] 回到家裏的網絡後，測試主機約 2–3 min 內 ping 不通手機（省電開着時，07:03、07:04 兩次探測失敗）。關掉省電後複測
      （2026-10-25，測試主機每秒 ping，時間戳用同一個時鐘）：手機 07:50:45 回到網絡，同一秒起 ping 通，之後 4.5 min 無間斷。
      多半是省電造成的（各只測了一次）。

## 遷移到 Ubuntu Server（2026-10-24 定的計劃：Arch 不留在手機上，隨時可以從備份刷回）

- [x] 整片備份當前的 Arch userdata（2026-10-25，boot-116，見 LOG.md）：救援模式下 `e2image -ra /dev/sda19 | zstd`，
      `arch-userdata-20261025.e2i.zst`（2.9 GB，sha256 `da2ec42c2e55cd80…`），測試主機 `~/sunstone-linux/backup/` 和構建主機
      `out/backup/` 各一份，不進 git（裡面有 Wi-Fi 配置、ssh 主機密鑰、EFS 副本）。解壓後 `e2fsck -fn` 乾淨。
      恢復：`tools/mkboot.sh rescue` 刷入救援鏡像，然後
      `zstd -dc arch-userdata-20261025.e2i.zst | ssh 手機 'dd of=/dev/sda19 bs=4M'`（先核對 PARTNAME=userdata），再刷回正式鏡像。
- [x] 內核配置補 Ubuntu Server 的功能（2026-10-25，boot-120/122）：`sunstone.config` 的「Ubuntu Server」一節。編進內核：
      AppArmor（LSM 列表裏，已啟用）、Yama、PSI、CHECKPOINT_RESTORE、overlayfs、FUSE、squashfs 的 xz/zstd/lzo、zswap；
      模塊：nftables 全套（ct/nat/masq/fib/reject/log/limit/compat）和 ufw 用的 xt 匹配、WireGuard、ipvlan、vxlan、dummy、
      zram、CIFS、ISO9660、dm-crypt、EROFS 等。舊式 iptables 表（NETFILTER_XTABLES_LEGACY）不開：Ubuntu 的 iptables/ufw
      走 nft 後端。**現在有模塊了**：build-kernel.sh 編譯並安裝到 `out/modules-m6`（含 modules.builtin），
      `tools/push-modules.sh` 推到 `/usr/lib/modules`。在 Arch 上驗證：nft 規則、iptables-nft 的 conntrack/multiport/
      recent/LOG、WireGuard 接口、overlay 掛載、erofs、zram 都可用。
      沒做：BPF LSM（systemd 報「BPF LSM hook not enabled」，RestrictFileSystems= 不生效；要 BPF_LSM + DEBUG_INFO_BTF）。（2026-10-25 做了，見「還不能用的」）
- [x] **Ubuntu Server 26.04 LTS 裝好並運行**（2026-10-25，boot-124/125，見 LOG.md）：`tools/mkrootfs-ubuntu.sh` 在手機上
      本地構建（debootstrap minbase + 挑選的包，apt pin 禁止 Ubuntu 內核/grub/flash-kernel；rmtfs.service（`-P`，直接用
      EFS 分區）和 qrtr-ns 在裝包前 mask；networkd 直接配，不用 netplan），搬過來 EFS 副本、Wi-Fi、ssh 主機密鑰、
      machine-id、RTC 偏移，chroot 裏跑 `sunstone-fw-install`，做成 8G ext4 鏡像；`tools/install-rootfs.sh` 經救援模式寫入
      userdata（讀回校驗），首次開機 `x-systemd.growfs` 擴到 102G。
- [x] 用户決定（2026-10-25）：先只用 root；**ufw 啟用，只放行 ssh**（加上 usb0 上給測試主機的 DHCP）。第一次啟用時
      內核缺 REJECT/hl/rt 模塊，規則只加載了一半，22 端口沒放行、默認拒絕卻生效，兩條 ssh 都斷了；事先設的 5 分鐘
      `ufw disable` 保險把它關掉。補上模塊（boot-126）後啟用無報錯，8080 從 Wi-Fi 和 USB 都連不上，重啟後照常加載。
      unattended-upgrades 已開（只裝安全更新，內核被 pin 擋住）。
- [x] **Lomiri（Ubuntu Touch 的外殼）作為可選桌面**（2026-10-25，用户確認觸摸、下拉菜單、側滑、頂欄大小、電源鍵都正常）：
      UBports 的系統要 Halium/Android 內核，用不了；Lomiri 0.5.0 在 Ubuntu universe 裡，跑在 Mir（msm KMS + freedreno）上，
      DSI-1 1080x2400@120。`tools/ubuntu/add-lomiri.sh` + `rootfs-overlay-lomiri/`：桌面用户 phone（uid 1000，無密碼，
      不能 ssh，sshd `AllowUsers root`），`systemctl start lomiri`（tty7 上的 logind 會話），默認仍是文本模式。
      踩過的坑：Mir 平台和鍵盤布局都是 Recommends（沒有布局 maliit 崩潰，連帶 Lomiri 每 8 s 重啟）；Lomiri 的網絡指示器
      拉進 NetworkManager，搶走 wlan0（Wi-Fi 斷，已 mask，build-rootfs.sh 也預先 mask）；libdeviceinfo 按
      /proc/device-tree/model 找機型配置，沒有時當桌面電腦（grid unit 8、橫屏，**觸摸不起作用**）→ sunstone.yaml
      （phone，GridUnit 26）；repowerd 只支持 Ubuntu Touch 的系統合成器（LSC），Mir 也沒有輸出電源管理協議，所以
      `sunstone-powerkey` 在 `GRAPHICS=1` 時自己熄屏：bl_power 關 + 觸摸屏 input inhibit。
- [x] **GNOME（Ubuntu 的默認桌面）作為可選桌面**（2026-10-25，用户確認：桌面、頂欄、Dock 都出來，橫屏方向可以，觸摸準確，
      電源鍵熄屏/亮屏效果很好；「有點卡，但符合預期」）：GNOME Shell 50.1（Wayland），`tools/ubuntu/add-gnome.sh` +
      `rootfs-overlay-gnome/`，約 270 個包（不帶 snapd、NetworkManager、GDM），`systemctl start gnome`（tty7 上 phone 的
      logind 會話，和 lomiri.service 互斥）。橫屏：`gdctl set --transform 90`，scale 2.5，系統默認 /etc/xdg/monitors.xml。
      電源鍵：GNOME 默認彈關機對話框 → gschema override（power-button-action nothing、不鎖屏、不休眠），sunstone-powerkey
      切換 mutter 的 `PowerSaveMode`（dpms 真正關閉，KMS）並在熄屏時暫停觸摸。沒有 GDM 時 gnome-shell 不提供
      ScreenShield（org.gnome.ScreenSaver），所以不走屏保。裝包時 polkit 在 polkitd 用户建好前被拉起而失敗，重啟即可。
- [x] **藍牙**（2026-10-25，boot-127/129）：WCN3988 藍牙在 QUP0 SE1 的高速 UART（0x4a84000，sm6375.dtsi 的 uart1，
      GPIO61-64），`qcom,wcn3988-bt`，供電 L9/L16/L2/L23（後三路和 WLAN 共用），swctrl GPIO69，固定的本地管理
      BD 地址 02:53:4e:00:00:11；GENI UART 要 `serial0` 別名（否則 `Invalid line -19`）。固件用手機 bluetooth_a 的
      apbtfw11.tlv / apnv11.bin（和 linux-firmware 的不同，`sunstone-fw-install` 拷到 updates/qca）。內核補 BT_LE、UHID、
      RFCOMM、BNEP、uinput；uhid 開機加載（modules-load.d），否則 BLE 鼠標 `input-hog profile accept failed`。
      用户測試：Logitech K380（經典藍牙 HID，配對碼）和 M575（BLE HoG，無配對碼）在 GNOME 下都正常、很流暢。
      配對要點：K380 只接受綁定（bluez 拒絕未綁定的經典 HID），要 `pairable on` + KeyboardDisplay agent + 及時輸入
      配對碼（配對碼也用 notify-send 彈到 GNOME）；GNOME 設置裡的藍牙一直在搜索、沒列出設備，沒查原因。
- [x] 用户決定（2026-10-25）：桌面用户 phone 設了密碼（只在手機上，不進倉庫）並加進 sudo 組；ssh 仍然只允許 root
      （`AllowUsers root`）。`add-lomiri.sh` / `add-gnome.sh` 建的 phone 照舊沒有密碼和 sudo，要時手動 `passwd phone`、
      `usermod -aG sudo phone`。GNOME 的鎖屏仍然關著（有密碼後可以打開）。
- [x] **Wi-Fi 改由 NetworkManager 管**（2026-10-25，用户要 GNOME 的 Wi-Fi 面板；用户確認：顯示已連接，能看到網絡列表）：
      `tools/ubuntu/wifi-to-networkmanager.sh`（`--revert` 退回）：wpa_supplicant 配置裡的網絡轉成 NM keyfile（只在手機上），
      `10-wlan0-networkmanager.network`（`Unmanaged=yes`）讓 networkd 放開 wlan0、overlay 的 20-wlan0.network 不動，
      `wpa_supplicant@wlan0` mask，NM 用 D-Bus 的 wpa_supplicant.service；usb0 仍是 networkd。NM：只管 wlan0、省電關、
      固定 MAC（掃描也不隨機）、DHCP client ID = MAC。地址變了（新的 DHCP 標識），測試主機的 reach-log 跟著改；
      路由器上給 02:53:4e:00:00:10 綁地址就能固定。`sunstone-wifi-add` 在 NM 運行時改用 `nmcli --ask`。
      build-rootfs.sh 仍然默認 networkd（服務器、無桌面時）。
- [x] **Wi-Fi 上 DSCP EF 的大包丟失**（原「reach-log 卡在認證前」，2026-10-26 查清並修好）：經 AP 發往手機、DSCP EF
      （語音類）且 IP 包 > 約 700 字節的幀時好時壞地全丟，OpenSSH 給交互式會話打 EF，所以 ssh 卡在 KEX（ping、普通流量
      是盡力而為類，不受影響）。原因：藍牙鼠標 M575 的 BLE 間隔 7.5 ms 佔共用天線，Wi-Fi 省電關着時共存機制不能讓 AP
      暫存，AP 發往手機的語音類幀失敗、降到 CCK 5.5 Mbit/s，長幀塞不進藍牙事件的空檔（證據見 LOG）。修法（用户選的）：
      有藍牙連接時才開 Wi-Fi 省電 —— `sunstone-wifi-btcoex`，由 `80-sunstone-btcoex.rules`（`hciN:句柄` 增刪）和
      `80-sunstone-wlan0.rules` 調用；NetworkManager `wifi.powersave=1`（不管）。驗證：斷開/重連時省電跟着關/開，連着
      鼠標和鍵盤時 EF 大包和 Wi-Fi ssh 正常，重啟後同樣。代價：連着藍牙時 Wi-Fi 延遲約 50 ms。測試主機上的
      監視腳本 `ef-mon.sh` 修好後記錄 7 次都正常（另 1 次是重啟），已停用刪除，日誌留在 logs/ef-mon.log。
- [ ] GNOME 鎖屏（用户 2026-10-25 想要「按一下熄屏、再按一下亮屏並顯示鎖屏」，先擱置，現在能熄屏就夠）：gnome-shell 只在
      GDM 存在時啟用 ScreenShield（解鎖靠 GDM 驗證密碼；沒有 GDM 時 org.gnome.ScreenSaver 是空接口）。方案：裝 gdm3，由它
      自動登錄 phone 啟動 GNOME（代替 gnome.service，仍手動 `systemctl start gdm`，開機文本模式；GDM 佔 tty1，停止後要
      讓 getty@tty1 回來），打開 lock-enabled（phone 已有密碼），sunstone-powerkey：第一下 org.gnome.ScreenSaver.Lock +
      PowerSaveMode 3，第二下 PowerSaveMode 0（顯示鎖屏）。解鎖用藍牙鍵盤或屏幕鍵盤。
- [ ] GNOME 偏卡：1080x2400@120 + 2.5 倍分數縮放壓在 Adreno 619（最高 650 MHz）上；60 Hz 模式有了但用户覺得不如
      120 Hz 絲滑；沒有 RealtimeKit（KMS 線程拿不到實時優先級）；GPU 700 MHz 檔（gpucc 沒有）。
- [ ] Lomiri：GridUnit 28 時每次啟動不到 1 s 就 SIGSEGV（26 正常），沒查原因；熄屏時 Mir 照樣 120 Hz 合成（不知道屏幕
      關了，也不顯示鎖屏）；網絡指示器沒有 NetworkManager 不顯示內容；音頻、相機在 Lomiri 裡沒試，沒有通話。
- [ ] tqftpserv 用的是 Ubuntu 的 1.1.1（可讀寫目錄在 /tmp，每次開機清空）；Arch 上是 git v1.3（/var/lib/tqftpserv）。
      modem 和 Wi-Fi 正常，有問題再換。
- [ ] 救援模式下寫 userdata 只有 6 MB/s（dropbear 單線程加密，8G 用 1352 s）：可以改用 `nc` 直傳。
- [ ] Ubuntu 上跑一次 24 h 穩定性測試（之前用户說先不開始）：在最終配置上（modem 修復、電源鍵、啟動成功標記、省電關、
      開機看門狗、ufw、藍牙；NetworkManager 管 Wi-Fi 時也要測一次重連）。

## 還不能用的（2026-10-25 整理；以前只寫在別的條目裡；2026-10-26 更新）

按這個順序一項項做（2026-10-25 定，依據手機原廠的 live DT，`ios-sunstone/out/dt/sunstone-live.dts`）。用到別人的代碼
（postmarketOS 補丁、下游驅動、第三方用戶態程序）先通讀、查安全性再用。

- [x] GNOME 設置裡的藍牙頁不列出設備（2026-10-25）：用户打開的是 Lomiri 的 `lomiri-system-settings`（「System Settings」，
      desktop 文件沒有 OnlyShowIn，在 GNOME 裡也顯示），它的藍牙頁不列設備、配對代理註冊報 Already Exists；bluez 本身正常
      （StartDiscovery 成功，找到設備）。`add-lomiri.sh` 在 /usr/local/share/applications 放一份 `OnlyShowIn=Lomiri;` 的副本
      蓋住它。GNOME 自己的「設置」→ 藍牙：用户確認設備都列出來，搜索圈一直轉（頁面開着時一直掃描，正常）。
- [x] BPF LSM（2026-10-25，boot-134）：`BPF_LSM`、`DEBUG_INFO_BTF`(+模塊)，為此要完整 DWARF（關 `DEBUG_INFO_REDUCED`）和
      `BPF_EVENTS`（kprobe/uprobe 事件、ftrace；arm64 的 BPF trampoline 掛在動態 ftrace 的函數入口 NOP 上）。
      `/sys/kernel/security/lsm` 有 bpf，`/sys/kernel/btf/vmlinux` 8 MB，systemd 不再報「BPF LSM hook not enabled」。
      代價：Image 43 → 63 MB（.BTF 8 MB，其餘是 ftrace 和重定位表），ABL 照常加載（以前最大 51 MB），內存多佔約 20 MB。
- [x] 振動馬達（2026-10-25，boot-134，用户確認）：下游 `qcom,qpnp-vibrator-ldo-v2` 沒有寄存器，只切 GPIO100 的上拉/下拉；
      這裡用主線 `gpio-vibrator` 驅動該腳（`vibrator` 節點），input 設備 `gpio-vibrator`（force feedback），
      `sunstone-vibrate [ms [次數]]`。
- [x] 紅外發射（2026-10-25，boot-134，用户用相機看到紅外燈在閃）：QUP0 SE2 的 SPI（`spi2`，GPIO45/46/56/57，GPI DMA，要開
      `gpi_dma0`），`ir-spi-led` 19.2 MHz，`/dev/lirc0`（只發不收）。`ir-ctl -d /dev/lirc0 -S nec:0x0408`（Ubuntu 的
      `ir-keytable` 包，已加進 build-rootfs.sh）。沒對真的電器測過。
- [ ] 蜂窩網絡：通話、數據、短信。**第一步做完（2026-10-25，boot-135/136）**：IPA v4.11（原廠 `qcom,ipa-hw-ver = <0x14>`），
      主線 `ipa` 模塊用 `qcom,sc7280-ipa` 的數據：寄存器 0x5840000、共享內存 0x5850000（0x3000，硬件報的大小）、GSI 0x5804000，
      IRQ SPI 257/259，SMMU 0x4a0/0x4a2，RPM IPA 時鐘，GSI 固件 `ipa_fws`（vendor_a 的 firmware/，`sunstone-fw-install` 拷貝，
      PAS 15，Linux 加載進 ipa-fw 載體），modem 表在 IMEM 0xc123000。開機 `IPA driver setup completed`、收到 modem running，
      `rmnet_ipa0` 出現，modem 和 Wi-Fi 不受影響。QMI 經 QRTR（`libqmi-utils`，`qmicli -d qrtr://0`）：DMS/UIM/NAS 應答，
      MPSS.HI.4.3.4，LTE + 5G NR；兩個卡槽 `no-atr-received`（**沒有 SIM 卡**），未註冊。operating mode 報 `shutting-down`（見下）。
      **數據能用（2026-10-26，boot-145，物聯網卡 1NCE）**：卡在卡槽 1，USIM `detected`；沒有 ModemManager 時沒人把 modem
      設成 online、也沒人建 provisioning 會話（`--dms-set-operating-mode=online`、`--uim-change-provisioning-session`
      手動做後註冊上）。ModemManager 1.25.95（`modemmanager`，已加進 build-rootfs.sh）用 qcom-soc 插件：端口 `qrtr0`（QMI）+
      `rmnet_ipa0`（net，udev 的 `ID_MM_QCOM_SOC` 規則；包裝上時網卡已存在，要 `udevadm trigger --action=change` 一次）。
      漫遊註冊在 LTE B3（20 MHz，RSRP −99 dBm，SNR 15.6 dB）。NetworkManager 連接 `1nce`（APN `iot.1nce.net`，只 IPv4，
      不自動連接、`ipv4.never-default`：這張卡流量很少）→ `qmapmux0.0@rmnet_ipa0`，經它 ping 8.8.8.8 4/4（約 90 ms）。
      modem 沒有 LTE-M/NB-IoT（DMS 能力只有 gsm/umts/lte/5gnr），LTE 硬件頻段 1/3/5/7/8/34/38–41（沒有 B20/B28）。
      剩下：短信（MM 報存儲 sm/me；1NCE 卡的短信額度已用完，後台發不出，2026-10-26 沒測成，要換卡或等額度）、新鏡像沒有 NetworkManager（build-rootfs 用 networkd）時怎麼撥號
      （mmcli --simple-connect + networkd 配地址，或換 NM）；通話要音頻。
      已知：`ipa: unexpected init_completed response`：ipa 是模塊，modem（內置 PAS 驅動）在 rootfs 掛載後先開始上電，ipa 錯過
      BEFORE_POWERUP，沒有拿 uC 的代理電源引用。影響只有 uC 的寄存器保持（要 AOSS QMP，這顆 RPM 架構的 SoC 沒有，函數直接
      返回）和 uC 的關閉命令，uC 本身初始化完成。要消除就得讓 modem 晚於 ipa 啟動。
- [ ] 音頻：揚聲器、聽筒、麥克風、耳機。**揚聲器能用（2026-10-25，boot-140，用户確認：三聲測試音、結尾無爆音）**。
      原廠：ADSP + APR，LPASS bolero 2.1（rx/tx/va macro + 兩條 SoundWire），codec WCD937x，揚聲器功放 SIA8159（i2c10 0x29，
      模擬輸入接 WCD 的 AUX，只經 I2C 開關）。主線：holi 的 LPASS 就是 sm6115 的（地址、LPI 腳功能、SoundWire hctl 都一樣），
      照 Linaro 的 qrb4210-rb2 音頻補丁（2024-12，sm6115 LPASS 節點 + wcd937x）寫進板級 DTS；ADSP 見 boot-137。
      本地補丁：0011（VA macro 報 v2.2.0，主線不認 → 按 2.1，下游叫 bolero 2.1），0012（`sia8159` 驅動：自己寫的，寄存器值和
      開關順序照廠商 sia81xx 驅動；掛在 WCD Playback 鏈路上，靠 mute_stream 在 prepare 末尾開、hw_free 開頭關——流停止時
      AUX 輸出會跳，功放開着就是爆音，先關功放則沒有，用户聽過確認）。
      現在的路徑：MultiMedia1 → RX_CODEC_DMA_RX_0 → RX0 → RX INT2 → RDAC3（RX3）→ AUX → SIA8159；手動用 amixer 設
      （`RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1`、`RX_MACRO RX0/RX1 MUX` AIF1_PB、`RX INT2_1 MIX1 INP0` RX0、`RDAC3_MUX` RX3、
      `AUX_RDAC Switch`、`LO Switch`，音量 `RX_RX2 Digital Volume`，84 = 0 dB，測試時 54）。功放增益未知（沒有增益寄存器的資料）。
      之後做了（見下）：UCM、主麥和副麥、耳機和插孔檢測；聽筒（EAR）還不出聲。已知告警：SoundWire 端口數比 sm6115 多一個
      （`din/dout-ports mismatch with controller`）；q6afe 的 LPASS 硬件 devote（0x100f6）被 ADSP 拒絕；SIA8159 的校準 CRC
      對不上（芯片裡就是廠商默認值 76 66 70，默認值自己也通不過校驗，寫回同樣的值）。測試時音量要小（用户要求）。
      **主麥克風能錄（2026-10-26，boot-147）**：原廠 mixer_paths_qrd.xml：主麥 AMIC1 → ADC1 → TX SoundWire 端口 1 →
      TX macro `SWR_MIC0`（handset-mic 的 DEC1；我們用 DEC0），副麥 AMIC3 = ADC2 `INP3` → `SWR_MIC4`（TX2），耳機麥 AMIC2 =
      ADC2 `INP2`，都走 TX_CDC_DMA_TX_3。sm6115 的 TX macro 用 v9_2 的 widget（`TX SWR_INPUTn`、`SWR_MICn`，和下游同名；
      不是 qcm6490 等的 `TX SWR_ADCn`）。DTS：MultiMedia3 作錄音前端（`MultiMedia3 Capture` ← `MM_UL3`）、`WCD Capture`
      鏈路（TX_CODEC_DMA_TX_3，`wcd937x 1` + `swr0` + `txmacro`）、AMIC → MIC BIAS、`TX SWR_INPUT0` ← `ADC1_OUTPUT`。
      手動路由：`MultiMedia3 Mixer TX_CODEC_DMA_TX_3`、`TX DEC0 MUX` SWR_MIC、`TX SMIC MUX0` SWR_MIC0、
      `TX_AIF1_CAP Mixer DEC0`、`ADC1_MIXER Switch`、`ADC1 Switch`，`arecord -D hw:0,2`（48 kHz）。底噪約 −88 dBFS，
      用户說話時峰值 −30 dBFS（`ADC1 Volume` 0；原廠初始 12，`TX_DEC0 Volume` 81）。
      **副麥也能錄（boot-149）**：`qcom,tx-port-mapping = <1 2 3 3>`（原廠的佈局：ADC1 → 主控端口 1 = `SWR_MIC0`，ADC2 →
      端口 2 = `SWR_MIC4`）。<1 1 2 3>（Linaro / qcm6490-idp）把 WCD 端口 1、2 都映到主控端口 1：qcom 的 SoundWire 主控給
      映到同一主控端口的從端口同樣的傳輸參數，兩路 ADC 同時開時聲道 1 的採樣撞在一起（約 −14 dBFS 的雜音，聲道 2 為 0，
      boot-148，加 `qcom,tx-channel-mapping` 也一樣）。雙聲道錄音：ch1 主麥（DEC0）、ch2 副麥（`ADC2 MUX` INP3、
      `TX SMIC MUX1` SWR_MIC4、DEC1），兩路獨立（相關 0.33）。注意 swr0 端口 3（MBHC）的 offset1 和端口 1 一樣是 1。
      用户對着底部說話時 ch1 高 8–14 dB，對着頂部時 ch2 高 8–10 dB：ch1（AMIC1）在底部，ch2（AMIC3）在頂部。
      **UCM（2026-10-26）**：`/usr/share/alsa/ucm2/conf.d/sm4250/Xiaomi-Sunstone.conf`（聲卡驅動名 sm4250，長名
      Xiaomi-Sunstone）+ `Xiaomi/sunstone/HiFi.conf`（rootfs-overlay；`alsa-ucm-conf` 加進 build-rootfs.sh）：HiFi 用例，
      設備 Speaker（RX0+RX1 混進 INT2，數字音量固定原廠的 78 = −6 dB，不給 PipeWire 硬件音量，桌面音量是軟件的，100% 即
      原廠最大）和 Mic（主麥，`TX_DEC0 Volume` 94，`ADC1 Volume` 12）。PipeWire 生成「Built-in Audio Speaker」和
      「Internal microphone」，播放（用户聽到）和錄音都通。**24 位不出聲**：PipeWire 默認 S24_LE，經 q6asm 播放沒有聲音
      （aplay S16_LE 的測試音麥克風錄得到，同樣的 S24_LE 錄不到）；WirePlumber 規則 `51-sunstone-s16.conf` 把這張卡的節點
      固定成 S16LE。內核裡 24 位的原因沒查（q6asm 的 PCM 格式塊？）。
      **耳機能用（boot-150）**：插孔檢測（MBHC）原來不工作，WCD 的中斷經 SoundWire 從設備告警上報，TX SoundWire 空閒時
      時鐘停止，告警到不了；原廠有 `swr_wake_irq`（TLMM GPIO 128），DTS 的 swr0 加上它（`interrupt-names = "core",
      "wakeup"`）後，總線休眠時插拔也即時檢測（阻抗約 52 Ω）。用户的耳機沒有麥克風，判成純耳機是對的；耳機麥（UCM
      Headset，`Mic Jack`）沒測。UCM Headphones（alsa-ucm-conf 的 rx-macro / wcd937x 序列，原廠的數字 84、模擬 20，
      `Headphone Jack`）：插上時 PipeWire 自動切過去。播完有爆音：RX macro 的 mute_stream 只靜音數據，SoundWire 在
      hw_free 停下時 HPH PA 還開着 → 本地補丁 0014（wcd937x 的 mute_stream 先關開着的 HPHL/HPHR/EAR PA，下一次流開始時
      DAPM 若還開着就重新打開），之後用户確認沒有爆音。
      **聽筒不響（2026-10-26，沒做完，UCM 裡先不放）**：原廠 handset 路徑（兩份 mixer_paths 一樣）：RX0 → RX INT0
      （`RX_EAR Mode` ON，DEM CLSH_DSM_OUT）→ WCD RX1 → `RDAC3_MUX` RX1 → `EAR_RDAC` → EAR PA，原廠設備樹只有一顆
      SIA8159，聽筒就在 WCD 的 EAR 上。主線照做：用户只聽到咔嗒聲（「噠噠噠」），頂部麥克風在 −30 dBFS 的 1 kHz 下也錄不到
      音調（揚聲器 −44 dBFS 時底部麥克風 −36 dBFS）。查過：① 主線要 `HPHL Switch`（RX1 的 SoundWire 通道）才有數據，
      不開時 HPHL PDM 看門狗反覆觸發（咔嗒加劇），開了看門狗不再觸發但仍無聲；② `RX HPH Mode` 拔耳機後是 CLS_H_INVALID，
      設 NORMAL/ULP 都一樣；③ 原廠 EAR DAC 上電無條件置 `CDC_COMP_CTL_0` 0x02（主線只在 comp1 開時），用 `HPHL_COMP Switch`
      試過，無聲；④ 換 RX3（揚聲器的數據通路，`LO Switch` 是它的 SoundWire 通道）餵 EAR 也無聲 → 問題在 EAR 模擬側。
      播放時寄存器：ANA_EAR 0x80、EAR_DAC_CON 0x80、EAR_COMPANDER_CTL 0x92、EAR_PATH_CTL 0。原廠 EAR PA 上電還有
      `PDM_WD_CTL0` 0x17/0x13（主線 0x07/0x03）和 `swr_slvdev_datapath_control`。對照源碼：CodeLinaro
      `platform/vendor/opensource/audio-kernel` 的 asoc/codecs/wcd937x/wcd937x.c。下一步：逐個比 EAR 相關寄存器
      （原廠 Android 下的值拿不到時，按下游代碼補寫）。通話本來也要 q6voice（主線沒有）。
      剩下：耳機麥（要帶麥的耳機）、副麥進 UCM（雙麥）。
- [ ] 傳感器（加速度計、陀螺儀、光線、距離）：在 ADSP 的 SSC 上。**加速度計、光線、距離、磁力計、指南針能讀（2026-10-26，
      boot-143，libssc 的 `ssccli`）**。SSC 是 QRTR 上的 QMI 服務 400（node 5）；它的文件經 fastrpc 由 hexagonrpcd 提供
      （DTS 裡 ADSP glink-edge 的 fastrpc 節點，compute-cb 3–7）。sensors PD 每次啟動都重寫註冊表：讀
      `persist/sensors/registry/sns_reg_version` 和 `registry/`，再對 `/vendor/etc/sensors/config` 的每個 JSON 寫
      `registry/../temp.json`、rename 進 `registry/`。Ubuntu 的 hexagonrpcd 0.4.0 只讀（上游 0.5.0 也是），第一次寫就失敗，
      registry 任務斷言（`sns_registry_sensor.c:154`），整個 ADSP 重啟（boot-141：接着 q6afe 重探測空指針，系統半掛 → 補丁 0013）。
      `tools/ubuntu/hexagonrpcd-sunstone.patch`（`add-hexagonrpcd.sh` 編進 `/usr/local/libexec/hexagonrpc/`，build-rootfs.sh
      調用）：`-W DIR` 可寫的註冊表（`/var/lib/hexagonrpcd/sensors`，第一次啟動從 sunstone-fw-install 的只讀副本複製，persist 分區
      從不寫），fwrite/fremove/frename，方法號 ≥ 31 的分派，大於 256 字節的輸入用 get_in_bufs2，調用失敗不再讓守護進程退出。
      陀螺儀也能讀（`ssccli --sensor gyroscope`，幫助裡沒列；靜止時三軸約 0，單位 rad/s，ssccli 印成 m/s）。
      **GNOME 自動旋轉能用（2026-10-26，用户確認四個方向都對）**：`tools/ubuntu/add-ssc.sh` 編 libssc v0.4.4 和
      iio-sensor-proxy master（SSC 支持在 3.8 之後才合併，按提交固定），build-rootfs.sh 調用；Ubuntu 的 3.8 包提供 unit、D-Bus、
      polkit。unit 的 `RestrictAddressFamilies` 要加 `AF_QIPCRTR`（drop-in），`79-sunstone-ssc.rules` 把 fastrpc-adsp 標成
      ssc-accel/light/compass（ssc-proximity 不開：上游因誤報默認關了，桌面也不用），安裝矩陣只反 x、y（postmarketOS 用的
      連 z 也反，正面朝上會報 face-down）。GNOME 的坑：會話啟動時接着藍牙鼠標，mutter 不在觸控模式，斷開鼠標後也不恢復
      （`PanelOrientationManaged` 一直 false，快捷設置裡沒有自動旋轉），要重啟會話；接着鼠標時不旋轉是 mutter 的設計。
      磁力計單位是 μT（2026-10-26 實測）：平放順、逆各轉一圈，X/Y 畫出圓心 (235, −36)、半徑 19.8、殘差 0.6 的圓（地磁水平
      分量的量級；mG 的話半徑會是 ~200），讀數大是約 470 μT 的硬鐵偏移（Z 約 −448，其中地磁只佔幾十）；`mag` 是未校準數據，
      SSC 的 mag_cal 和指南針自己校準。陀螺儀同時積分：順時針一圈 369°、轉回後 −2°（13 Hz 採樣，約 2.5%），和磁力計
      朝向的變化一致（符號相反，坐標約定）。
      剩下：GNOME 自動亮度（光線傳感器已經在 iio-sensor-proxy 裡，沒試）；
      PD 還會找本地接口 `sns_registry`（我們沒有，返回錯誤後它繼續）、`pcba_config`（華勤 sysfs，沒有）。
- [x] NFC：**本機沒有**（2026-10-26 查證，不做）。原廠設備樹的公共部分有 `st21nfc@8`（i2c@4a80000 = QUP0 SE0，VEN GPIO6、
      IRQ GPIO9、clkreq GPIO7），vendor 也帶 ST 的 HAL、固件和 `st21nfc.ko`，但都是各版本共用的：NFC 的 HAL 和 STFlashTool 只在
      `ro.boot.product.hardware.sku=sunstone_global` 時啟動。ABL（LinuxLoader）的 SKU 取自 SMEM 條目 135 的第一個 u32 v，
      按 v % 16 查表（0 cn、1 global、2 in、3 cn_new、4/5 moonstone_p、6 x、7 cn，其他 unknow），只有 global 帶 NFC。
      本機的值（一個只讀的臨時模塊 `qcom_smem_get(135)` 讀到）不是 global。硬件上也確認了（boot-144）：開 i2c0、GPIO6 輸出高
      （pinctrl debugfs `out high`）後整條總線掃描沒有任何應答，VEN 低時也沒有；同樣的掃描在 i2c10 上能看到沒綁驅動的 0x28、0x4e、0x66。
- [x] 攝像頭（2026-10-26，boot-154–167；自動對焦除外，見下）：本機三個傳感器，供電都在 i2c10 的 WL2866D（本地補丁 0017）上，I/O 是 GPIO38
      的 CAM_VIO。CAMSS 按 qcm2290 的 TFE/CSID 340 + CSIPHY 1.2.1（本地補丁 0018），沒有 interconnect。
  - [x] 前攝 OV08D10（cci1 0x10，CSIPHY3，2 lane，MCLK3 24 MHz，復位 GPIO37，LDO2 + LDO4）：主線驅動 + 0019（rotation）；
        RAW10 抓幀、libcamera simple 管線 + 軟件 ISP（1632x1224 約 29 fps，3200x2400 30 fps，緩衝區在 system dma-heap），
        PipeWire / GNOME 相機（Snapshot，用户確認豎屏方向正確；橫屏差 90°，是 Snapshot 不管屏幕旋轉）。
  - [x] 主攝 OV48B2Q（cci0 主機 0 的 0x10，CSIPHY0，4 lane，MCLK0 24 MHz，復位 GPIO34，LDO1 + LDO3）：本地補丁 0020，
        MTK ov48b2q_mipi_raw 的表，一個模式 4000x3000 30 fps（軟件 ISP 15 fps）；rotation 270。用户確認方向正確、有點糊。
  - [x] 主攝 2000x1500（0022）：原廠 CamX 模組數據（`com.qti.sensormodule.*.bin`，數值在去重的數值池裡）裡 4000x3000 和
        2000x1500 不同的寄存器，時鐘照 MTK 的表；30 fps（最高 90），軟件 ISP 1920x1440 30 fps。用户：流暢多了，照片能存。
  - [x] 主攝對焦馬達：DW9800W（cci0 主機 0 的 0x0c，寄存器 0 讀出 0xf2），主線 dw9719 驅動的 `dongwoon,dw9800k`（原廠
        CamX 模組數據的初始化相同）；電源 GPIO50（`cam_vaf`，接在 cam_vio 後面：總線上拉在 cam_vio 上）。軟件 ISP 沒有
        自動對焦：udev（`71-sunstone-camera-focus.rules`）把位置定在 480（遠景最清晰在 464–480，350 以下鏡頭不動）。
        用户：遠處清楚了一些。馬達只在主攝出流時通電（0023/0024：PipeWire 一直開着它的節點，原來線圈一直通電、
        cam_vio 常開）；DW9800 在鏡頭移動時丟掉新位置（0026：等狀態寄存器 0x05 的忙位）。
  - [x] 主攝：自動對焦（2026-10-27）：libcamera 0.7.0（和 Ubuntu 同版本）加本地補丁 `tools/ubuntu/libcamera-sunstone-af.patch`，
        `add-libcamera-af.sh` 編進 /usr/local（同 SONAME，`libdir=lib/aarch64-linux-gnu`，否則加載器先找到 Ubuntu 的；
        裝完檢查 PipeWire 插件要的符號都在）。軟件 ISP 的統計加清晰度（中心 1/9，同色相鄰像素差的平方和，按亮度² 歸一），
        simple IPA 加 `Af`，simple 管線經 CameraLens 移鏡頭。第二版（用户第一次試：能對上但不靈敏、可能虛焦；日誌：手持
        移動時掃出虛焦峰、虛焦後基準低不再重掃、過曝畫面也「對焦」）：畫面穩定（兩個採樣亮度差 <8%、清晰度差 <25%）且
        亮度 12–210 才掃，掃描中亮度變 >15% 放棄，掃完驗證（<70% 掃描最好值就重掃，最多兩次），場景變化後先在原位 ±32
        細查、峰在邊上才全掃，細掃 16 + 拋物線插值，最後從下方接近（音圈回差），對比度 <1.5 倍或清晰度 <0.001 算失敗。
        實測距離（用户對着 2 m 和窗外）：無窮遠約 420、2 m 約 438，約 `420 + 34000/距離 mm`（30 cm ≈ 530）；以前「遠景最清晰
        464–480」其實約 0.7 m。`ov48b2q.yaml`：384–1023，`fixedPosition: 438`。固定對焦（GoPro 式，約 1 m 到無窮遠）：
        `sunstone-camera-focus fixed|auto`（寫 /usr/local/etc/libcamera/configuration.yaml 的 `software_isp.focus`，重啟
        PipeWire），默認自動。udev 起始位置改 438。cam：一次掃描約 1.6 s；平坦畫面判失敗停 438；固定模式直接 438。
        用户第二輪 Snapshot 試第二版之後的改動（回差、門檻）沒再試。
  - [ ] 主攝：EEPROM 0x51 的鏡頭陰影/白平衡校準沒用。
  - [x] 後置 2 MP SC202CS（cci1 0x36，CSIPHY2，1 lane，MCLK2 24 MHz，復位 GPIO36，LDO4）：本地補丁 0021（驅動，Motorola
        MTK 驅動的初始化表），1600x1200 30 fps；rotation 90。單色模組（原始幀四個 Bayer 位置相差 1 % 以內），驅動照樣報
        SBGGR10，軟件 ISP 出灰度畫面。用户確認方向正確、黑白。
  - [x] 閃光燈：KTD2691（cci0 主機 1 的 0x64；CamX 模組數據 `ktd2691`），軟件上是 LM36011（ID 寄存器 0x06 = 0x08，
        模式 0x01：0 關、2 手電筒、3 閃光），主線 lm3601x + 0025（vio = cam_vio 只在讀寫寄存器時開）+ 0027（模式寄存器
        volatile）；`/sys/class/leds/white:flash`，手電筒 36 級（最大 106 mA），閃光 1.0 A、0.4 s。用户：三步都正常。
        GPIO51（原廠 CUSTOM_GPIO2，大概是 STROBE 腳）沒用。
- [ ] 指紋：Goodix / FPC，TZ 管的 SPI（GPIO 13–16 保留給 TZ），要 TZ 裡的可信應用，**基本做不了**。
- [x] **USB OTG**（2026-10-26，boot-172；用户要的）：Hub（Genesys 0610）+ SD 讀卡器（Ubuntu 安裝盤，只讀 23 MB/s）+
      AX88179 網卡（cdc_ncm）都能用；拔掉後升壓關、充電恢復、回到 device，USB ssh 正常。Type-C 芯片：原廠 DT 寫
      `richtek,rt1711h@4e`（i2c10，中斷 GPIO59），讀 TCPC 寄存器是 **Hynetek HUSB311**（VID 0x2E99、PID 0x0311），主線
      `tcpci_rt1711h`。做法：USB 改扁平 `qcom,snps-dwc3`（legacy glue 在 otg 模式只靠 extcon 設 VBUS override，扁平
      glue 跟着 role switch 設）、`dr_mode = "otg"` + `usb-role-switch`（默認 peripheral，TCPM 加載前 gadget 照常）；
      HUSB311 + `usb-c-connector`（雙角色、Try.SNK、`pd-disable`、作源時 Rp 1.5A）；VBUS = bq25890 的 `usb-otg-vbus`。
      SC89890H 只置 OTG_CONFIG 時不升壓，要先關 CHG_CONFIG → 本地補丁 0028。
- [x] GNOME 自動掛載（2026-10-26，boot-174）：ISO/FAT 要 `NLS_UTF8`（已開，另加 Joliet、zisofs、exFAT、NTFS3、UDF）；
      ISO 分區插上即掛；ext4 按 Ubuntu 的 `64-ext4.rules` 不自動掛（點擊掛載）；內部 UFS 用 `80-sunstone-ufs-hidden.rules`
      從 udisks 隱藏。FAT/exFAT 的 U 盤沒實測。
- [x] USB 3.0：做不了。官方規格是 USB Type-C 2.0；下游 DT 的 QMP USB3/DP 組合 PHY（0x1630000）是 Blair 參考板的，
      其初始化序列和主線 `sm8250_usb3dpphy_cfg` 的表 127/144 項相同（13 項通道調參不同）。
- [x] **GNOME Snapshot 橫屏**（2026-10-26，用户：「軟件很好」）：Snapshot 50.0 和上游 main 都不管屏幕旋轉（預覽只按
      攝像頭安裝角度的 `image-orientation` 標籤轉正，橫屏時是側着的豎條；照片按傳感器原樣存，1920x1080、無 EXIF 方向）。
      `tools/ubuntu/add-snapshot.sh` + `snapshot-sunstone.patch`：aperture 在攝像頭源 bin 的出口改寫標籤 = 傳感器方向 +
      mutter `DisplayConfig` 主顯示器的旋轉（前攝取反，它的預覽在後面鏡像），變化時在下一幀前補發；拍照分支加
      `videoflip`，按快門時按同一個方向設好（camerabin 不把標籤傳給拍照分支：第一版用 `auto`，照片沒轉），之後去掉方向
      標籤。裝在 /usr/local（Ubuntu 的包保留），在手機上編譯約 12 min。用户：預覽各方向都正，豎屏照片 1080x1920、
      橫屏 1920x1080，都是正的。沒做：錄像（標籤同樣不一定到錄像分支，沒試）。
- [x] iio-sensor-proxy 開機時沒有加速度計（2026-10-26 boot-174，`HasAccelerometer` false，GNOME 不能自動旋轉；修好）：
      QRTR 服務 400 在 ADSP 起來後就有了（8.3 s 時已在），各傳感器要等 hexagonrpcd 送完註冊表（約 9–12 s）才註冊。
      drop-in 改為等 `ssccli --sensor accelerometer` 能打開（和 proxy 一樣經 libssc），最多 2 min（沒有 ssccli 時不等），`TimeoutStartSec=180`。
      兩次重啟：等了 2.5 s、3.4 s，都有加速度計（GNOME 自動旋轉另外要求會話啟動時沒有連着鼠標）。
- [x] 主攝的「咔」聲（2026-10-26，用户：不影響壽命就不修）：切到主攝和離開主攝時各一聲，開時較響。聽音對比：鏡頭目標 0
      （不移動）也響、只給馬達上電（不開傳感器）也響；電源開着時手動讓 DW9800 休眠、喚醒、切模式都不響 → 來自馬達電源
      cam_vaf 通斷的瞬間，不是鏡頭移動。可選的修法（cam_vaf 常開、空閒時只讓芯片休眠，連帶 cam_vio 常開）沒做。
- [ ] OTG 剩下的：PD 關着（充電器按 Rp 給 5 V；要快充或數據角色交換再開）；角色切換時 `dwc3-qcom: remote wakeup
      not configured`（沒配 wakeup-source）；udev 的 `mtp-probe` 不存在（libmtp 規則，無害）；接 OTG 時手機用電池
      給外設供電，長時間接大功率設備會耗盡電池。

## 以後

- [ ] 超聲波測距（聲吶），**實驗版 `sunstone-sonar`（2026-10-26）**：揚聲器 → 主麥 18–21 kHz 比信號高 10–15 dB、SNR 約
      30 dB（3 s 掃頻實測；頂部麥 −12..−22 dB、SNR 11–16）。24 個 2 ms 18–21 kHz chirp（−30 dBFS，測時 sink 臨時 100%），
      匹配濾波 + 包絡，按直達聲對齊平均；平放在桌上時桌面、機身、房間的反射比直達聲低約 25 dB，蓋住半米外的物體 →
      `--calibrate` 存無物體時的背景（未取包絡的波形；播放和錄音同一時鐘，逐樣點重複），之後相減，靜止時背景壓低 17 dB。
      A4 書在 50 cm：回波 0.49/1.02/1.57 m，30 cm：0.62/0.92 m，都是距離的倍數（書和手機之間來回反彈），按間距給
      距離（一次 0.280 m）；人在旁邊走動、伸手時回波整組變。**墊高後好用**：手機放在 15–20 cm 高的書堆上、底邊齊邊緣、
      人站開，不校準（`--raw`）牆在 50 cm 測 0.488 m（−10 dB，兩次相同），100 cm 測 0.952–0.957 m（4 次），誤差 2–5%。
      報告規則：回波序列（倍數）要包含最強回波，否則取比最強弱不到 3 dB 的最近回波（1 m 時房間裡 1.15 m 的反射有時更強）。
      剩下：numpy（`python3-numpy`）是手動裝的，沒進 build-rootfs；距離的比例誤差（−2..−5%）沒校；
      有人時的穩定性。原來的計劃：
揚聲器放一段短的近超聲掃頻（18–20 kHz，例如 5–10 ms 的 chirp），麥克風錄回聲，和發出的信號做
      互相關，找直達聲之後的回聲峰，延遲 × 聲速 / 2 就是距離。48 kHz 採樣時一個樣點約 3.6 mm，安靜房間裏預計 0.2–3 m。
      紅外燈做不了：它只發不收（SPI 驅動的 38 kHz 遙控 LED，手機沒有紅外接收），光的飛行時間要皮秒級計時。
      前提：麥克風（見「音頻」，WCD TX AMIC → TX macro）。要確認的：揚聲器和 SIA8159 在 18–20 kHz 的響應、麥克風的採樣率和
      頻響、揚聲器到麥克風的直達聲和機殼振動怎麼扣掉。測試時音量要小、先告訴用户（用户要求）。
- [x] **wlroots0.20 是本地補丁版**（0.20.2-1.1，`/etc/pacman.conf` 裡 IgnorePkg）：Arch 升級 wlroots0.20 或 phoc 換
      wlroots 版本時，用 `sunstone-build-wlroots-phosh` 重編，再解除 IgnorePkg。（2026-10-25 關閉：只關 Arch，Arch 已不在手機上，備份可以刷回）；腳本在 `rootfs-overlay-arch/`。

- [x] **板上熱敏電阻和 `cpu-unk0/1`**（2026-10-27，boot-175/176）：
      `cpu-unk0/1`（tsens 11、12）是 A78 簇的第 3、4 個傳感器（下游叫 cpu-1-2/cpu-1-3，從它們限 cpu@600），綁到 cpu6 策略；
      模擬 92 °C 時只有 cpu6 降一檔。熱敏電阻照下游：PMK8350 ADC7 的 `xo_therm`（0x644），PM6125 ADC5 的 `pa_therm1`
      （THM1）、`quiet_therm`（THM2）、`msm_therm`、`rear_cam_flash_therm`、`pa_therm2`（PM6125 GPIO3/6/7 = ADC5 GPIO1/3/4，
      引腳高阻）。PM6125 的 ADC_TM 硬件只有 4 個通道（NUM_BTM 讀出 4，boot-175 按 6 個寫時 probe 報 Invalid channel 4），
      和下游一樣 `msm_therm` 走 IIO 輪詢（`generic-adc-thermal`，5 s）。下游的 `rfc_cam_therm`（GPIO4）讀出 −40 °C（開路），
      本機沒焊，不用。mainline pm6125.dtsi 的 `xo_therm`（0x4c）本板沒接，刪掉；PMK8350 的 vref_1p25 讀 1.000 V（ADC7 換算
      不對），不列。溫區：`quiet-thermal`（下游的皮膚傳感器）55 °C 被動（cpu0、cpu6、GPU，1 s 輪詢）、80 °C 關機，模擬 60 °C
      時三者各降一檔、清除後恢復；`xo`、`pa-therm1/2`、`msm`、`cam-flash` 只有 125 °C 的 critical（下游的 step 區都是
      disabled，Xiaomi 用戶態限頻；這裡沒有 modem PA 的冷卻設備）。空閒充電時都在 27–30 °C。健康日誌加了 `skin=`、`xo=`。
- [ ] 熱管理的剩餘部分：電池溫區（sm5602）沒有觸發點，充電靠充電器的 JEITA（TS 腳）；PM6125 溫度報警的閾值。
- [x] QRNG（2026-10-27 查過，不做）：下游 `qcom,msm-rng`@0x4453000（`qcom,no-qrng-config`）。7.3 的 qcom-rng 只把
      `qcom,trng` 註冊成 hwrng，`qcom,prng`/`prng-ee` 只綁定、什麼都不做；同地址的 agatti 在主線是 prng-ee，沒有資料說 holi
      的是 TRNG，不能硬寫成 trng 給它記滿熵。內核不缺熵（沒有硬件 RNG 時 `crng init done` 在 4.1 s），CPU 有 AES/SHA 指令，
      加密引擎（qcrypto）也就不需要。
- [ ] 日誌刷屏：`ath10k_snoc: chan info: invalid frequency 0 (idx 41 out of bounds)`（18 h 482 次），
      `wcd937x_codec: clk already disabled`（12 次，大概是音頻流開關時）；2026-10-27 發現，沒查。
- [x] RTC 偏移：timesyncd 經 Wi-Fi 對時，`rtc-offset-save.path` 在對時後保存偏移（M5）。
- [x] pacman 鏡像站換成就近的（現在重定向到美國，約 1.9 MB/s）；不再需要測試主機的 SOCKS 隧道。（2026-10-25 關閉：只關 Arch，Arch 已不在手機上，備份可以刷回）。
- [x] 內核模塊：現在所有驅動都編進內核，rootfs 裡沒有 `/lib/modules`；以後要裝模塊（`modules_install` + 推送）。
      （2026-10-25 做完：build-kernel.sh 編譯並安裝模塊，`tools/push-modules.sh`，mkrootfs-ubuntu.sh 也裝進新 root。）
- [x] DTS 合併（2026-10-25）：m1 → … → m6 → m6d 的串聯合成一個板級 `dts/sm4375-xiaomi-sunstone.dts`（每個節點一次，
      覆蓋過的值直接寫最終值），加 `-rescue.dts`（救援模式，shim 不開看門狗）。校驗：兩者經 cpp + `dtc -O dts -s` 展開排序、
      去掉 phandle 行後，只差 model 字符串。舊文件和二分樹（m6a/e/f/g、m3rescue）在 git tag `dts-milestones`。
      `tools/mkboot.sh sunstone` / `rescue`，內核默認 m6。
- [x] **microSD**（2026-10-27，boot-178）：`sdhc_2`（mainline sm6375.dtsi 已有，disabled）+ PM6125 L22（卡 2.96 V）/ L5（I/O，
      1.8 V UHS-I）+ 插卡檢測 GPIO94 高有效，和原廠、Sony pdx225 一樣。GPIO94 跟的是卡托不是卡：只有 SIM 時也是高
      （核心試一次，沒有卡應答，不報錯），拔卡托時跳變。實測 SanDisk 64 GB SDXC：UHS-I SDR104 202 MHz、1.8 V 信號；
      重新分區成 GPT 一個 ext4（標籤 `sdcard`），寫 28 MB/s（direct，2 GiB）、讀 69–74 MiB/s，1 GiB 隨機數據丟緩存後
      sha256 一致，內核無 mmc 錯誤。開機自動掛載（2026-10-27）：fstab `LABEL=sdcard /srv/sd ext4 rw,noatime,nofail,
      x-systemd.device-timeout=10s 0 2`（build-rootfs.sh 也寫）；有卡時開機即掛，沒有這個標籤的卡時不報錯、不拖慢開機
      （改標籤模擬：multi-user 7.9 s，有卡 6.0 s）。拔卡托時 systemd 卸載，插回不會自己再掛 → `80-sunstone-sdcard.rules`
      （標籤 sdcard 的 ext4 出現時 `SYSTEMD_WANTS=srv-sd.mount`），unbind/bind 控制器驗證會重新掛上。掛着時拔卡托是不乾淨的
      卸載（那次 fsck 回放了日誌，結果 clean）：要拔先 `umount /srv/sd`。
      注意：Ubuntu 26.04 的 dd 是 uutils 0.10.0，`iflag=direct` 讀文件報 `IO error: Invalid input`（不是內核問題）。
- [x] 熱插拔卡托（SIM 和 SD 在同一個卡托）後 modem 沒有主 GW provisioning 會話：UIM 報 USIM `detected`，ModemManager 反覆建
      modem 又以 `sim-missing` 失敗，重啟 MM 也一樣。手動 `qmicli -d qrtr://0 --uim-change-provisioning-session=
      "slot=1,activate=yes,session-type=primary-gw-provisioning,aid=<USIM 的 AID>"` 後重啟 MM，馬上註冊（2026-10-27）。
      **自動恢復（2026-10-27）**：`sunstone-sim-watch.service` 每 10 s 查 UIM 卡狀態，連續兩次「有 USIM、沒有主會話」就按
      該卡的 AID 激活，40 s 後 MM 的 modem 不在或 failed 就重啟 MM。用 `activate=no` 模擬：20 s 內激活，modem 一直 registered；
      正常開機時不動作（modem 自己開會話）。用户真的拔插卡托（15:53:38）：26 s 後激活，modem 自己回到 registered（LTE + 5G NR），
      不用重啟 MM。
