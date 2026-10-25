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
- [ ] 面板的 60 Hz 模式（下游 dfps 120/60）、亮度曲線（`bl-inverted-dbv`、最小亮度 4）、HBM/調光命令。
      用户反饋（boot-87）：亮度 80 和 300 看起來差不多（讀回值正確）。查三星 `bl-dcs-type-ss-ea` 和
      `bl-inverted-dbv` 在下游 dsi_panel.c 裏怎麼換算 51h 的兩個字節（字節序、是否取反），再看整個 4–2047 範圍的實際效果。
- [ ] phoc 打印「No panel found for compatibles」：gmobile 的面板數據庫裡沒有 sunstone（圓角/挖孔），可以給 gmobile 提交。
- [x] DTS：`qcom,mdss-dsc-slice-height` 的坑記在面板驅動裡；m6e/m6f/m6g 二分樹已刪（2026-10-25，見下面的 DTS 合併）。
- [ ] Phosh 的 Wi-Fi 開關需要 NetworkManager（現在是 networkd + wpa_supplicant）。

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
- [ ] 最終配置上再跑 24 h（modem 修復、電源鍵、啟動成功標記、省電關、開機看門狗），期間故意觸發看門狗復位和 panic。
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
      沒做：BPF LSM（systemd 報「BPF LSM hook not enabled」，RestrictFileSystems= 不生效；要 BPF_LSM + DEBUG_INFO_BTF）。
- [x] **Ubuntu Server 26.04 LTS 裝好並運行**（2026-10-25，boot-124/125，見 LOG.md）：`tools/mkrootfs-ubuntu.sh` 在手機上
      本地構建（debootstrap minbase + 挑選的包，apt pin 禁止 Ubuntu 內核/grub/flash-kernel；rmtfs.service（`-P`，直接用
      EFS 分區）和 qrtr-ns 在裝包前 mask；networkd 直接配，不用 netplan），搬過來 EFS 副本、Wi-Fi、ssh 主機密鑰、
      machine-id、RTC 偏移，chroot 裏跑 `sunstone-fw-install`，做成 8G ext4 鏡像；`tools/install-rootfs.sh` 經救援模式寫入
      userdata（讀回校驗），首次開機 `x-systemd.growfs` 擴到 102G。
- [x] 用户決定（2026-10-25）：先只用 root；**ufw 啟用，只放行 ssh**（加上 usb0 上給測試主機的 DHCP）。第一次啟用時
      內核缺 REJECT/hl/rt 模塊，規則只加載了一半，22 端口沒放行、默認拒絕卻生效，兩條 ssh 都斷了；事先設的 5 分鐘
      `ufw disable` 保險把它關掉。補上模塊（boot-126）後啟用無報錯，8080 從 Wi-Fi 和 USB 都連不上，重啟後照常加載。
      unattended-upgrades 已開（只裝安全更新，內核被 pin 擋住）。
- [ ] 桌面：用户問 Ubuntu Touch。UBports 的系統要 Halium/Android 內核，用不了；它的外殼 Lomiri（0.5.0，Qt + Mir）在
      Ubuntu 26.04 universe 裡，424 個包 / 628 MB，這台手機上沒試過。Phosh 0.54：444 個包 / 713 MB，Arch 上要打
      wlroots 補丁。都沒有音頻、相機、通話；作為可選會話，默認仍是文本模式。
- [ ] tqftpserv 用的是 Ubuntu 的 1.1.1（可讀寫目錄在 /tmp，每次開機清空）；Arch 上是 git v1.3（/var/lib/tqftpserv）。
      modem 和 Wi-Fi 正常，有問題再換。
- [ ] 救援模式下寫 userdata 只有 6 MB/s（dropbear 單線程加密，8G 用 1352 s）：可以改用 `nc` 直傳。
- [ ] Ubuntu 上跑一次 24 h 穩定性測試（之前用户說先不開始）。

## 以後

- [ ] **wlroots0.20 是本地補丁版**（0.20.2-1.1，`/etc/pacman.conf` 裡 IgnorePkg）：Arch 升級 wlroots0.20 或 phoc 換
      wlroots 版本時，用 `sunstone-build-wlroots-phosh` 重編，再解除 IgnorePkg。

- [ ] 熱管理：tsens 已有溫度，CPU 冷卻設備和電池溫度保護（充電器 JEITA）。
- [ ] PMK8350 ADC 通道、PM6125 溫度報警的閾值。
- [x] RTC 偏移：timesyncd 經 Wi-Fi 對時，`rtc-offset-save.path` 在對時後保存偏移（M5）。
- [ ] pacman 鏡像站換成就近的（現在重定向到美國，約 1.9 MB/s）；不再需要測試主機的 SOCKS 隧道。
- [ ] 內核模塊：現在所有驅動都編進內核，rootfs 裡沒有 `/lib/modules`；以後要裝模塊（`modules_install` + 推送）。
- [x] DTS 合併（2026-10-25）：m1 → … → m6 → m6d 的串聯合成一個板級 `dts/sm4375-xiaomi-sunstone.dts`（每個節點一次，
      覆蓋過的值直接寫最終值），加 `-rescue.dts`（救援模式，shim 不開看門狗）。校驗：兩者經 cpp + `dtc -O dts -s` 展開排序、
      去掉 phandle 行後，只差 model 字符串。舊文件和二分樹（m6a/e/f/g、m3rescue）在 git tag `dts-milestones`。
      `tools/mkboot.sh sunstone` / `rescue`，內核默認 m6。
