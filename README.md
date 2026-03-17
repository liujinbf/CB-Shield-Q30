# CB-Shield-Q30 🛡️

> 基于 OpenWrt 的跨境电商专用路由器固件 · JCG Q30 PRO (MT7981B)

## 功能特性 (V3.0 终极黄金版)

- **多 SSID & VLAN 隔离** — 办公 / 访客 / 电商业务三网物理隔离
- **网络流加速 (Offloading)** — 开启软硬件流加速，双核占用 < 5%，从容跑满千兆带宽
- **SQM/Cake 流量整形** — 保障电商网（TikTok/直播）上行视频流 0 缓冲延迟
- **Passwall 原生代理** — 满血版支持 (包含 Xray/V2Ray/SS 等全部协议及其配套组件)
- **底层指纹消除 (防关联)** — TTL=128 伪装 / OOB 阻断 WebRTC / Nftables 层级 DNS 强制劫持回源 / 国际化 NTP 替换
- **Kill Switch & MAC 随机化** — 代理掉线瞬间强制切断网卡流 (秒级)，且每次开机自动重置电商 BSSID 随机 MAC 防追踪
- **KJWS 现代仪表盘** — 蓝白配色商务风格原生 LuCI 原生界面，实时风控显示
- **GitHub Actions CI** — 云端自动化编译部署

## 硬件平台 (JCG Q30 PRO)

| 参数 | 规格 |
|------|------|
| 芯片 | MediaTek MT7981B (Filogic 820) |
| CPU | 64位 双核 ARMv8 Cortex-A53 @ 1.3GHz |
| 内存 | 256MB DDR3/DDR4 |
| Flash | 128MB SPI NAND (Winbond W25Q1G) |
| 网络 | 1 WAN + 4 LAN (全千兆) |
| 无线 | Wi-Fi 6 AX3000 (MT7976C: 2.4G 2T2R + 5G 2T2R) |

## 网络架构

| VLAN | 子网 | 用途 | SSID |
|------|------|------|------|
| VLAN 10 | 192.168.10.0/24 | 办公网络 | CB-Shield-Office / Office-5G |
| VLAN 20 | 192.168.20.0/24 | 访客网络 | CB-Shield-Guest |
| VLAN 30 | 192.168.30.0/24 | 电商业务 | CB-Shield-ECom / ECom-5G |

## 快速开始

### 自动编译

1. Fork 本仓库到你的 GitHub
2. 进入 **Actions**
3. 开发版固件使用 **Build Dev Firmware**
4. 稳定版固件使用 **Build Stable Firmware**
5. 等待编译完成后，从 Artifact 下载 `factory.bin` 和 `sysupgrade.bin`

### 本地主编译 (推荐)

```bash
# Linux / WSL2 / 自托管 Runner
bash scripts/local-build.sh stable
```

产物会输出到 `artifacts/stable/`。

### 手动编译

```bash
# 1. 克隆 OpenWrt 源码
git clone https://git.openwrt.org/openwrt/openwrt.git
cd openwrt

# 2. 复制配置
cp /path/to/CB-Shield-Q30/feeds.conf.default .
cp /path/to/CB-Shield-Q30/.config .

# 3. 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 4. 准备工程
bash /path/to/CB-Shield-Q30/scripts/prepare-openwrt.sh "$(pwd)" stable

# 5. 预编译自定义包
bash /path/to/CB-Shield-Q30/scripts/package-preflight.sh "$(pwd)"

# 6. 编译
make download -j8
make -j$(nproc) V=s
```

## 项目结构

```
CB-Shield-Q30/
├── .config                    编译配置 (mediatek/filogic)
├── feeds.conf.default         Feeds 源定义 (含 Passwall)
├── .github/workflows/         Dev/Stable 双工作流
├── profiles/                  Dev/Stable 编译差异配置
├── scripts/                   本地主编译与预检查脚本
├── files/etc/config/          UCI 网络/防火墙/DHCP/风控配置
├── packages/cb-riskcontrol/   IP 风控检测包
└── luci-theme-cbshield/       KJWS LuCI 主题
    ├── Makefile               OpenWrt 包定义
    ├── htdocs/                静态资源 (CSS/JS/图标)
    └── luasrc/                Lua 控制器和视图模板
```

## 风控系统

风控脚本每 5 分钟检测 WAN IP，评估风险：

| 风险因素 | 加分 | 说明 |
|----------|------|------|
| 代理 IP | +50 | IP 经过代理转发 |
| 托管/数据中心 IP | +30 | 属于云服务器 |
| 可疑 ISP/组织 | +20 | 名称含 VPN/Proxy 等关键词 |

当风险分数超过阈值（默认 70 分），可执行：
- `warn` — 记录日志告警
- `disconnect` — 断网重连
- `switch_proxy` — 切换 Passwall 代理节点

## 许可证

MIT License · © KJWS
