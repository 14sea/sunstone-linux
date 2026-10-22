# sunstone Linux 計劃

目標：在 Redmi Note 12 5G（`sunstone`，Qualcomm SM4375 "blair" / Snapdragon 4 Gen 1，6x A55 + 2x A78，
Adreno 619，8 GB）上用**主線 Linux 內核**跑起一個**預編譯的 Arch Linux ARM 或 Debian**。

起點：2026-10-22。主線基線 Linux **7.3**（kernel.org 當日最新穩定版），以後跟進新的穩定版。

## 約束與決定（2026-10-22，用戶）

- 走主線內核路線（不是 Android 內核 + chroot，也不是 crDroid 下游 5.4 內核原生啟動）。
- 不需要和 iOS、crDroid 共存：兩者隨時可以刷回手機（`ios-sunstone` 項目、crDroid ROM）。
- **只動 `boot_a`，後期加上 `userdata`**。不碰 bootloader（ABL/XBL 等）、fastboot、recovery、
  `vendor_boot`、`dtbo`、`vbmeta`、modem、persist、modemst/fsg。slot b 的 crDroid 和它的 recovery 保留，
  用來救機和讀日誌。備份：測試主機上的 slot-a 分區備份和各 LUN 的 GPT 頭尾（不進 git）。
- 顯示的推進順序：
  1. **局部勝利**：從測試主機 ssh 進手機（USB 網卡）。
  2. **控制台**：屏幕上的文本控制台。
  3. 有餘力再做圖形桌面。
- 發行版：預編譯的 **Arch Linux ARM**（aarch64 通用 rootfs）或 **Debian arm64**；預編譯的用不了，再交叉編譯。
- 構建機：本機（20 核，460 GB 空閒，`aarch64-linux-gnu-gcc` 13，`fakeroot`、`mke2fs`、
  `qemu-aarch64-static`、`dtc`）。測試主機（手機接在上面，4 核）負責刷機和拉日誌。如果要改為在
  測試主機上交叉編譯，再補裝工具鏈。

## 啟動方案

ABL 從 `vendor_boot` 裡按 msm-id/board-id 挑一個**下游** DTB（再疊加 `dtbo`）交給內核，主線內核用不了。
兩種解決辦法：

1. **shim 鏈式加載（首選）**：沿用 `ios-sunstone` 的 boot shim。ABL 把 `boot_a` 裡的 shim 當內核加載，
   shim 忽略 ABL 的 DTB，從 `_end` 後面找到 payload，加一種新類型 `SWEETLNX`：
   `Image + 主線 DTB + initramfs + cmdline`。按 arm64 啟動協議跳轉：Image 放在 2 MB 對齊的 RAM，
   MMU 和 D-cache 關閉，x0 = DTB 物理地址，x1-x3 = 0，EL1。副核由 Linux 自己用 PSCI 拉起。
   好處：只寫 `boot_a`；跳轉前 shim 能在屏幕上打印診斷信息。
   不帶 `gpu.c`（Linux 自己初始化 GPU）。
2. 備選：自己做一個帶主線 DTB 的 `vendor_boot_a`（加上空的 `dtbo_a`），像 postmarketOS 那樣讓 ABL 直接
   啟動主線內核。要動 `vendor_boot`/`dtbo`，違反上面的約束，只在 shim 方案走不通時再考慮。

注意：ABL 能加載的內核大小有上限，主線 `defconfig` 的 Image 有 40 MB 左右。shim + payload 要控制體積：
用精簡的 sunstone 配置，必要時壓縮 Image，由 shim 解壓。`boot_a` 是 128 MiB。

## 調試手段（手機沒有串口）

| 手段 | 何時可用 | 說明 |
| --- | --- | --- |
| shim 屏幕控制台 | 跳轉前 | 紅底文字：payload 校驗、各段地址、跳轉地址 |
| simplefb + fbcon | M1 起 | DTB 裡聲明 ABL 留下的 splash：`0x85200000`，a8r8g8b8，1080x2400，stride 4320；內核日誌直接上屏 |
| pstore/ramoops | M1 起 | 和下游佈局一致：`0xd0000000`、2 MB、console 1 MB、pmsg 1 MB。崩潰或重啟後進 crDroid recovery，讀 `/sys/fs/pstore/console-ramoops*` |
| USB gadget | M2 起 | CDC-NCM/ECM 網卡 + ACM 串口；測試主機 ssh / `screen` |

## 里程碑

每一步都有明確的完成標準，一步一步來；每次啟動都按順序編號，記到 `LOG.md`。

### M0 環境
- 拉 Linux 7.3 源碼；確認 `arch/arm64/boot/dts/qcom/sm6375.dtsi` 的現狀：已有 CPU、cpufreq、RPM 電源域、
  SMMU、IPCC、GLINK、ADSP/CDSP/MPSS PAS、QUP/GENI、SPMI、USB HS、SDHCI、tsens、WCN3990；
  缺 UFS、MDSS/DPU/DSI、dispcc、GPU 節點。
  **7.3 實測（2026-10-22）**：`sm6375.dtsi` 和上面一致（2482 行，唯一的板級 DTS 是 Sony
  `sm6375-sony-xperia-murray-pdx225.dts`）。驅動側已有：`dispcc-sm6375`、`gcc-sm6375`、`gpucc-sm6375`、
  `pinctrl-sm6375`、DPU catalog `dpu_6_9_sm6375.h`、Adreno a619_holi（chip id `0x06010901`），以及
  `pm6125`/`pmk8350`/`pmr735a` 的 dtsi。缺口：**沒有 sm6375 的 interconnect 驅動**（帶寬投票要靠
  bootloader 留下的狀態，或者先不接 icc）；**`phy-qcom-qmp-ufs` 沒有 sm6375 的條目**（只有同代
  sm6115 的表，M3 要對照下游 DT 的 UFS PHY 補一個）。
- 從 `ios-sunstone` 拷 shim（去掉 `gpu.c`），加上構建和刷機腳本（沿用 `tools-host/chain-boot.sh` 的流程）。
- 完成標準：本機能構建出 `boot_a` 鏡像，內含 shim + 一個測試 payload。

### M1 第一次跳進 Linux
- 最小 sunstone DTS：基於 `sm6375.dtsi`；`memory` 包含三段 DDR；`reserved-memory` 照抄 sunstone 的**實測** DT
  （下游 `vb0.dts` / live DT：hyp、xbl、smem `0x80900000`、各 carve-out、ramoops）；simplefb；ramoops。
  先只開 CPU0（`maxcpus=1` 或 DTS 裡只留一個核），其餘外設全部禁用。
- initramfs：靜態 busybox，`/init` 打印一行就進 shell（沒有輸入也沒關係）。
- 完成標準：屏幕上出現 fbcon 打印的內核日誌和 `/init` 的輸出，或者 pstore 裡能讀到。

### M2 局部勝利：ssh
- DTS：USB 控制器（dwc3 `0x4e00000`）改為 `dr_mode = "peripheral"`，加上 HS PHY。
- initramfs：configfs 配出 NCM（或 ECM）gadget，固定 IP（手機 `192.168.7.2/24`，測試主機
  `192.168.7.1`），dropbear + 測試主機的公鑰。
- 完成標準：在測試主機上 `ssh root@192.168.7.2` 成功。

### M3 rootfs 和發行版
- DTS：UFS（`ufshc@4804000` + QMP UFS PHY + 時鐘/電源/復位，按下游 DT 和同代 SoC 的主線寫法來寫）。
- rootfs：Arch Linux ARM aarch64 通用 tarball（默認），或 Debian arm64。用 `fakeroot` + `mke2fs -d`
  製作 ext4 鏡像（不需要 sudo，屬主信息保留），稀疏化後刷到 `userdata`（會覆蓋 iOS 的 root）。
- initramfs 掛載 `userdata` 後 `switch_root`，systemd 起來，openssh 和 USB 網卡保持可用。
- 完成標準：ssh 進入 Arch/Debian，`pacman`/`apt` 能用（先經 USB 網卡共享測試主機的網絡）。

### M4 控制台和基礎硬件
- 屏幕控制台：simplefb 上跑 getty/登錄提示（屏幕常亮，不能調亮度）。
- 8 個核和 cpufreq（EPSS）、按鍵（PM6125 PON + GPIO 音量鍵）、RTC（PMK8350）、溫度傳感器。
- 觸摸：FT5452 在 `0x38`。TrustZone 只給 QUP 開了 GSI DMA，FIFO 用不了，主線大概也要用 `i2c-gpio`
  （GPIO19/20，復位 21，中斷 22），驅動是 `edt-ft5x06`。
- 電池：SM5602 電量計（主線沒有驅動，要寫；寄存器知識來自 `SweetBattery`），SC8989X 充電器
  （先試主線 `bq25890` 驅動）。
- 完成標準：屏幕上有登錄提示，按鍵和觸摸有 evdev 事件，`/sys/class/power_supply` 有數據。

### M5 Wi-Fi
- MPSS PAS（firmware 在 `modem_a`），rmtfs、pd-mapper、tqftpserv（發行版裡都有包），WLAN SMMU stream `0x80`，
  ath10k snoc（WCN3990）。
- 完成標準：手機自己連上 Wi-Fi，可以去掉 USB 網卡。

### M6 圖形桌面（有餘力時）
- 顯示：dispcc + MDSS/DPU（`dpu_sm6375` 在主線裡）+ DSI0（`0x5e94000`）+ 面板驅動（xiaomi m17，Samsung DDIC，
  DSC video）。面板驅動可以用 linux-mdss-dsi-panel-driver-generator 從下游 DT 生成。
- GPU：a619_holi 節點（GMU wrapper，zap PAS 13），Mesa freedreno。
- 桌面：Phosh/Sway/Weston 選一個。
- 後續可選：ADSP 傳感器（hexagonrpcd + libssc，`ios-sunstone` 已經驗證過 registry 那條路）、音頻、調製解調器數據。

## 可以從 ios-sunstone 復用的實測知識

- 地址：GIC `0xf200000`/`0xf240000`，UFS `0x4804000`，splash `0x85200000`，PS_HOLD `0x440b000`，
  IMEM 重啟原因 `0xc12565c`，EPSS `0xfd91000`/`0xfd92000`，DSI0 `0x5e94000`，GPU `0x5900000`，
  GPU SMMU `0x5940000`，GPU CC `0x5990000`，SMEM `0x80900000`，IPCC `0x208000`，RPM 消息 RAM `0x45f0000`。
- 內存：DDR `0x80000000`+`0x3bb00000`，`0xc0000000`+3 GiB，`0x1_80000000`+4 GiB；carve-out 都在 4 GiB 以下；
  32 位 DMA 引擎（DSI 命令 DMA 等）要用 4 GiB 以下的內存。
- 遠程處理器：modem PAS 4（`0x8b800000`，256 MiB），ADSP PAS 1（`0x86700000`，40 MiB），IPCC 門鈴：
  modem client 2，ADSP client 3。
- 面板：DCS `0x28`/`0x29` 開關屏，`0x51` 亮度（DBV 4..0x7ff，高字節在前）。
- 重啟進 fastboot：ABL 讀的是 PM6125 PON `SOFT_RB_SPARE`（SPMI），單寫 IMEM cookie 沒用。
- 下游 DT 存檔：`ios-sunstone/research/dt/vb0.dts`（stock vendor_boot 裡的 DTB），以及
  `ios-sunstone/out/dt/` 下的 live DT（含設備標識，不進 git）。

## 風險

- `reserved-memory` 和實機不一致 → 碰到 XPU 保護區域時無聲掛死。對策：照抄實測 DT；靠 pstore 看日誌。
- 主線的 Gunyah/hyp 相關假設：SMMU 是虛擬化的（`ios-sunstone` 裡 GPU SMMU 的訪問會陷入 hypervisor）。
- UFS PHY 和 ICE 的初始化細節；USB PHY 和 VBUS 檢測；DSC 面板。
- ABL 對 shim + payload 的體積上限。

## 目錄規劃

| 路徑 | 內容 |
| --- | --- |
| `PLAN.md` | 本計劃 |
| `LOG.md` | 每次構建和啟動的記錄（編號、輸入、結果、日誌位置） |
| `shim/` | 從 `ios-sunstone` 拷來的 boot shim + `SWEETLNX` payload |
| `dts/` | `sm4375-xiaomi-sunstone.dts` 及需要的 dtsi 補丁 |
| `kernel/` | 內核配置（`sunstone_defconfig` 片段）和補丁；源碼樹放在 `src/`（不進 git） |
| `initramfs/` | `/init` 腳本、busybox/dropbear 的構建 |
| `rootfs/` | 製作 Arch/Debian ext4 鏡像的腳本 |
| `tools/` | 打包、刷機、拉日誌的腳本（主機相關的設置在本地配置文件裡） |
| `out/`, `src/`, `downloads/` | 構建產物、源碼、下載的 tarball（不進 git） |
