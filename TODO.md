# sunstone Linux 待辦

按優先順序。M5（Wi-Fi）走通後先回來處理「遺留問題」，再進 M6。現在在 M6（圖形桌面）。

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
- [ ] snap 掛載時 `SQUASHFS error: Xattrs in filesystem, these will be ignored`（兩個 snap，掛載正常）：`sunstone.config` 已加
      `SQUASHFS_XATTR=y`（Ubuntu 的內核也開），下一次編內核時生效。
- [ ] pstore 不可用：開 ECC 後普通 reboot 能留下 console 記錄，但 DDR 在復位期間衰減嚴重（411 個塊無法糾正）；
      panic 走的是進 fastboot 的路徑，ABL 可能還會覆蓋。M1 時記錄基本完整（16 KB 約 10 處位翻轉）。ramoops 的
      ECC/dmesg 區從沒進過倉庫裏的 DTS（試驗時是臨時改的）。
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
      未做：`cpu-unk0/1` 未綁定；電池溫區（sm5602）沒有觸發點，充電靠充電器的 JEITA（TS 腳）；
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
- [ ] reach-log（測試主機）裝 Ubuntu 後有一段時間每次 ssh 都卡在認證前（sshd `Timeout before authentication`），手動 ssh
      正常，重啟 reach-log 後恢復；sshd 沒有 PerSourcePenalties 記錄。原因未明。
- [ ] GNOME 鎖屏（用户 2026-10-25 想要「按一下熄屏、再按一下亮屏並顯示鎖屏」，先擱置，現在能熄屏就夠）：gnome-shell 只在
      GDM 存在時啟用 ScreenShield（解鎖靠 GDM 驗證密碼；沒有 GDM 時 org.gnome.ScreenSaver 是空接口）。方案：裝 gdm3，由它
      自動登錄 phone 啟動 GNOME（代替 gnome.service，仍手動 `systemctl start gdm`，開機文本模式；GDM 佔 tty1，停止後要
      讓 getty@tty1 回來），打開 lock-enabled（phone 已有密碼），sunstone-powerkey：第一下 org.gnome.ScreenSaver.Lock +
      PowerSaveMode 3，第二下 PowerSaveMode 0（顯示鎖屏）。解鎖用藍牙鍵盤或屏幕鍵盤。
- [ ] GNOME 偏卡：1080x2400@120 + 2.5 倍分數縮放壓在 Adreno 619（最高 650 MHz）上；60 Hz 模式有了但用户覺得不如
      120 Hz 絲滑；沒有 RealtimeKit（KMS 線程拿不到實時優先級）；GPU 700 MHz 檔（gpucc 沒有）。
- [ ] Lomiri：GridUnit 28 時每次啟動不到 1 s 就 SIGSEGV（26 正常），沒查原因；熄屏時 Mir 照樣 120 Hz 合成（不知道屏幕
      關了，也不顯示鎖屏）；網絡指示器沒有 NetworkManager 不顯示內容；沒有音頻、相機、通話。
- [ ] tqftpserv 用的是 Ubuntu 的 1.1.1（可讀寫目錄在 /tmp，每次開機清空）；Arch 上是 git v1.3（/var/lib/tqftpserv）。
      modem 和 Wi-Fi 正常，有問題再換。
- [ ] 救援模式下寫 userdata 只有 6 MB/s（dropbear 單線程加密，8G 用 1352 s）：可以改用 `nc` 直傳。
- [ ] Ubuntu 上跑一次 24 h 穩定性測試（之前用户說先不開始）：在最終配置上（modem 修復、電源鍵、啟動成功標記、省電關、
      開機看門狗、ufw、藍牙；NetworkManager 管 Wi-Fi 時也要測一次重連）。

## 還不能用的（2026-10-25 整理；以前只寫在別的條目裡）

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
- [ ] 蜂窩網絡：通話、數據、短信。手機原廠 DT 的 IPA 是 `qcom,ipa-hw-ver = <0x14>`（下游枚舉 = IPA v4.11，主線
      `drivers/net/ipa` 支持，sc7280 就是 v4.11），0x5800000 / GSI 0x5804000，IRQ SPI 257/259，固件 `ipa_fws`（PAS 15），
      SMMU 流 0x4a0–0x4a3。**手機裡沒有 SIM 卡**：先只做 IPA 和 modem 握手、rmnet 出現；數據、短信等有卡再測。
- [ ] 音頻：揚聲器、聽筒、麥克風、耳機。原廠是 ADSP + APR（`qcom,msm-audio-apr`、q6core、q6 dai），LPASS 的 rx/tx/va macro +
      SoundWire，codec WCD937x（WCD938x 節點是 disabled；主線有 wcd937x 驅動），揚聲器功放 SIA81xx（I2C 0x29，**主線沒有
      驅動**），聲卡 `qcom,holi-asoc-snd`。sm6375.dtsi 有 ADSP 的 remoteproc，板級 DTS 沒啟用。
- [ ] 傳感器（加速度計、陀螺儀、光線、距離）：在 ADSP 的 SSC 上，要 hexagonrpcd + libssc（postmarketOS，第三方代碼）。
- [ ] NFC：ST21NFC（I2C 0x08），查主線 st-nci 是否兼容。
- [ ] 攝像頭：原廠 IFE/OPE/CCI（cam-isp）；主線 CAMSS 不支持 sm6375，sm6375.dtsi 也沒有 CAMSS / CCI 節點。工作量很大，大概率不做。
- [ ] 指紋：Goodix / FPC，TZ 管的 SPI（GPIO 13–16 保留給 TZ），要 TZ 裡的可信應用，**基本做不了**。

## 以後

- [x] **wlroots0.20 是本地補丁版**（0.20.2-1.1，`/etc/pacman.conf` 裡 IgnorePkg）：Arch 升級 wlroots0.20 或 phoc 換
      wlroots 版本時，用 `sunstone-build-wlroots-phosh` 重編，再解除 IgnorePkg。（2026-10-25 關閉：只關 Arch，Arch 已不在手機上，備份可以刷回）；腳本在 `rootfs-overlay-arch/`。

- [ ] 熱管理的剩餘部分（CPU/GPU 的 cooling-maps 已做，見「服務器」）：`cpu-unk0/1`（tsens 11、12）沒綁定，電池溫區（sm5602）
      沒有觸發點，充電靠充電器的 JEITA（TS 腳）。
- [ ] PMK8350 ADC 通道、PM6125 溫度報警的閾值。
- [x] RTC 偏移：timesyncd 經 Wi-Fi 對時，`rtc-offset-save.path` 在對時後保存偏移（M5）。
- [x] pacman 鏡像站換成就近的（現在重定向到美國，約 1.9 MB/s）；不再需要測試主機的 SOCKS 隧道。（2026-10-25 關閉：只關 Arch，Arch 已不在手機上，備份可以刷回）。
- [x] 內核模塊：現在所有驅動都編進內核，rootfs 裡沒有 `/lib/modules`；以後要裝模塊（`modules_install` + 推送）。
      （2026-10-25 做完：build-kernel.sh 編譯並安裝模塊，`tools/push-modules.sh`，mkrootfs-ubuntu.sh 也裝進新 root。）
- [x] DTS 合併（2026-10-25）：m1 → … → m6 → m6d 的串聯合成一個板級 `dts/sm4375-xiaomi-sunstone.dts`（每個節點一次，
      覆蓋過的值直接寫最終值），加 `-rescue.dts`（救援模式，shim 不開看門狗）。校驗：兩者經 cpp + `dtc -O dts -s` 展開排序、
      去掉 phandle 行後，只差 model 字符串。舊文件和二分樹（m6a/e/f/g、m3rescue）在 git tag `dts-milestones`。
      `tools/mkboot.sh sunstone` / `rescue`，內核默認 m6。
