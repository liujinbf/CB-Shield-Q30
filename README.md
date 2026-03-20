# CB-Shield-Q30

基于 OpenWrt 23.05 的 JCG Q30 PRO 定制固件仓库，当前定位是单网络、双频办公 WiFi、单代理框架和轻量运维能力的组合方案。

## 项目定位

- 仅保留 `lan` 单网络模型，不再维护 `shop1..shop5` 多网络编排
- 默认启用 `office_24g` 和 `office_5g` 两个接入点，统一桥接到 `lan`
- 代理框架优先兼容 OpenClash，其次兼容 Passwall
- 通过自定义运维组件提供风控、健康检查、HA、DNS 守护、事件日志和首启向导
- 通过 LuCI 自定义页面聚合展示系统状态、风险状态和运维入口

## 关键目录

- `.github/workflows/`：GitHub Actions 构建流程
- `files/`：镜像覆盖文件和首次启动默认配置
- `luci-theme-cbshield/`：LuCI 控制器、页面和静态资源
- `packages/cb-riskcontrol/`：自定义运维和风控组件包
- `profiles/`：`dev` / `stable` 构建差异配置
- `scripts/`：构建、预检和辅助脚本

## 自定义能力

### 运维与风控

- `cb-riskcontrol`：检测出口 IP 风险并按阈值执行告警、重连 WAN 或重启代理
- `cb-healthcheck`：检查代理、风控、Portal 和 WiFi 状态，支持自动拉起
- `cb-ha-monitor`：通过探测目标地址判断链路健康，并在异常时执行恢复动作
- `cb-dns-guard`：检测单网络模型下的 DNS 守护状态
- `cb-safe-upgrade`：升级前检查镜像存在性、SHA256、`sysupgrade -T` 和空间条件
- `cb-eventlog`：记录风控、健康检查、恢复动作和升级检查事件
- `cb-wizard`：首次启动向导

### LuCI 页面

- 仪表盘：系统负载、风险状态、网络状态概览
- IP 风控：查看出口 IP、风险分数、最近一次动作和 Portal 入口
- 网络状态：查看 WAN、LAN、WiFi 和在线客户端状态
- 运维中心：查看健康检查、HA、DNS 状态并手动执行升级前检查
- 事件时间线：查看最近事件
- 首次向导：初始化密码、时区、WAN 协议和 WiFi 信息

## 构建方式

### Kwrt 运行时叠加

当 `factory.bin` 在不死 U-Boot 恢复页上存在兼容问题时，优先使用这条路线：

1. 先刷已经验证可启动的 `Kwrt/openwrt.ai` Q30 固件
2. 再安装本仓库生成的 `CB-Shield` 运行时叠加包

生成叠加包：

```bash
bash scripts/build-kwrt-runtime-bundle.sh
```

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\kwrt-runtime.ps1 build
```

完整说明见 [kwrt-runtime-workflow.md](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/docs/kwrt-runtime-workflow.md)。

### GitHub Actions

可直接触发以下工作流：

- `Build Dev Firmware`
- `Build Stable Firmware`

### 本地构建

建议在 Linux、WSL2 或自托管 Linux Runner 中执行：

```bash
bash scripts/local-build.sh stable
```

输出目录：

- `artifacts/stable/`
- `artifacts/dev/`

### 手工准备 OpenWrt 源码树

```bash
git clone https://git.openwrt.org/openwrt/openwrt.git
cd openwrt

cp /path/to/CB-Shield-Q30/feeds.conf.default .
cp /path/to/CB-Shield-Q30/.config .

bash /path/to/CB-Shield-Q30/scripts/prepare-openwrt.sh "$(pwd)" stable
bash /path/to/CB-Shield-Q30/scripts/package-preflight.sh "$(pwd)"

make download -j8
make -j"$(nproc)" V=s
```

## 常用脚本

- [local-build.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/local-build.sh)：本地完整构建
- [prepare-openwrt.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/prepare-openwrt.sh)：准备 OpenWrt 源码树
- [package-preflight.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/package-preflight.sh)：预编译自定义包
- [ci-smoke.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/ci-smoke.sh)：仓库级静态冒烟检查
- [serial-capture.ps1](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/serial-capture.ps1)：串口日志抓取

## 首次刷机后建议检查

1. 首次向导是否正常弹出
2. 管理员密码、时区和 WAN 协议是否生效
3. `office_24g` 与 `office_5g` 是否已创建并桥接到 `lan`
4. OpenClash 或 Passwall 是否按预期启动
5. 风控、健康检查、HA、DNS 守护服务是否正常启动
6. LuCI 自定义页面与 API 是否可以正常访问
7. 本地 Portal 是否可以通过 `http://路由器IP:8080/` 访问

## 当前边界

- 不再实现多 WiFi 独立出口 IP
- 不再内置 `shop` 模板引擎
- kill switch 和 HA 保护的是单一全局代理出口
- `cb-safe-upgrade` 仅负责升级前检查，不等同于完整双分区回滚体系
- Portal 配置文件已随固件打包到 `files/www/cb-portal/portal_config.json`
- `Kwrt-src/` 仅作为本地参考目录，不参与仓库索引和构建输入

## 许可证

仓库当前按 MIT 思路维护，最终以各包目录内的 LICENSE 和文件头声明为准。
