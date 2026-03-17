# CB-Shield-Q30

基于 OpenWrt 23.05 的 JCG Q30 PRO 专用固件仓库。

当前仓库已经收敛为一套更适合 Q30 PRO 硬件能力的方案：`单网络 + 双频 WiFi + 单代理框架 + 轻量风控运维`。本文档以当前代码实现为准，不再沿用早期多 `shop` / 多 WiFi 编排文案。

## 项目定位

当前固件的目标不是多业务 WiFi 出口编排，而是提供一版可以稳定运行的专用代理固件：

- 保留 `lan` 单网络模型
- 保留 `2.4G + 5G` 双频办公 WiFi
- 通过单一代理框架承接全局分流
- 保留风险检测、健康检查、HA 监控、DNS 防泄漏、事件日志与升级前检查
- 提供自定义 LuCI 运维页面，面向非技术运营人员暴露核心状态和常用操作

## 当前方案

### 1. 网络模型

- `lan`：唯一内部网络
- `office_24g`：2.4GHz 办公无线，挂到 `lan`
- `office_5g`：5GHz 办公无线，挂到 `lan`
- 不再创建 `shop1..shop5`
- 不再保留多 WiFi 模板编排与独立出口策略

相关文件：

- [90_v3_optimizations](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/files/etc/uci-defaults/90_v3_optimizations)
- [dhcp](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/files/etc/config/dhcp)
- [firewall](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/files/etc/config/firewall)
- [sqm](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/files/etc/config/sqm)

### 2. 代理框架

当前仓库默认保留“单代理框架”思路：

- 优先兼容 OpenClash
- 兼容 Passwall 作为备选
- 分流逻辑由代理框架自身负责
- 不再额外维护 WiFi 级分流或多出口编排层

自定义运维组件会自动识别当前可用代理服务，并在页面与健康检查中统一展示为“代理服务”。

相关文件：

- [.config](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/.config)
- [api.lua](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/luasrc/controller/cbshield/api.lua)
- [index.lua](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/luasrc/controller/cbshield/index.lua)

### 3. 风控与运维

`packages/cb-riskcontrol` 当前承载以下功能：

- `cb-riskcontrol`
  - 检测当前出口 IP 风险
  - 支持按阈值执行告警、重连 WAN 或重启代理服务
  - 内置全局 kill switch 保护逻辑
- `cb-healthcheck`
  - 检查代理服务、风控守护、Portal 和 WiFi 状态
- `cb-ha-monitor`
  - 通过探测目标地址判断线路健康
  - 在线路异常时执行代理服务恢复动作
- `cb-dns-guard`
  - 在单网络模式下维护 DNS 防泄漏状态
- `cb-safe-upgrade`
  - 在升级前检查镜像存在性、SHA256、`sysupgrade -T`、可用空间等条件
- `cb-eventlog`
  - 记录风控、健康检查、恢复动作和升级检查事件
- `cb-wizard`
  - 首次启动向导

相关文件：

- [cb-riskcontrol.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/packages/cb-riskcontrol/files/cb-riskcontrol.sh)
- [cb-healthcheck.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/packages/cb-riskcontrol/files/cb-healthcheck.sh)
- [cb-ha-monitor.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/packages/cb-riskcontrol/files/cb-ha-monitor.sh)
- [cb-dns-guard.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/packages/cb-riskcontrol/files/cb-dns-guard.sh)
- [cb-safe-upgrade.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/packages/cb-riskcontrol/files/cb-safe-upgrade.sh)
- [cb-wizard.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/packages/cb-riskcontrol/files/cb-wizard.sh)

### 4. LuCI 运维页面

当前自定义 LuCI 页面已经切换到单网络视角：

- 仪表盘
- IP 风控
- 网络状态
- 运维中心
- 事件时间线
- 首次向导

页面重点展示：

- WAN / LAN 状态
- 2.4G / 5G 无线状态
- 代理服务状态
- 风险分数与出口 IP
- HA / DNS / 自检状态
- 事件日志

相关文件：

- [dashboard.htm](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/luasrc/view/cbshield/dashboard.htm)
- [riskcontrol.htm](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/luasrc/view/cbshield/riskcontrol.htm)
- [network_status.htm](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/luasrc/view/cbshield/network_status.htm)
- [ops_center.htm](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/luasrc/view/cbshield/ops_center.htm)
- [timeline.htm](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/luasrc/view/cbshield/timeline.htm)
- [dashboard.js](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/luci-theme-cbshield/htdocs/luci-static/cbshield/js/dashboard.js)

## 当前边界

为避免误解，以下几点需要明确：

- 当前固件不再实现多 WiFi 独立海外 IP
- 当前固件不再内置多 `shop` 模板引擎
- 当前 kill switch 与 HA 逻辑保护的是“单一全局代理出口”
- `cb-safe-upgrade` 是升级前检查工具，不是完整双分区回滚系统
- 代理线路自动切换能力主要依赖代理框架自身；自定义脚本提供的是恢复与守护能力

## 首次启动建议

首次刷机后，建议至少验证以下内容：

1. 首次向导是否正常弹出
2. 管理员密码、时区、WAN 协议是否生效
3. `office_24g` 与 `office_5g` 是否按预期创建并接入 `lan`
4. OpenClash 或 Passwall 是否按预期启动
5. 风控、健康检查、HA、DNS 守护服务是否正常启动
6. LuCI 自定义页面与 API 是否可正常访问

## 构建方式

### GitHub Actions

可直接触发：

- `Build Dev Firmware`
- `Build Stable Firmware`

### 本地构建

建议在 Linux / WSL2 / 自托管 Runner 中执行：

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

## 目录结构

```text
CB-Shield-Q30/
├── .github/workflows/          GitHub Actions 构建流程
├── files/                      固件覆盖文件与首启脚本
├── luci-theme-cbshield/        自定义 LuCI 控制器、页面与静态资源
├── packages/cb-riskcontrol/    自定义运维与风控组件包
├── profiles/                   dev / stable 构建差异配置
├── scripts/                    构建、预检与辅助脚本
├── .config                     OpenWrt 编译配置
├── feeds.conf.default          Feeds 定义
└── portal_config.json          Portal 外部配置示例
```

## 常用脚本

- [local-build.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/local-build.sh)：本地完整构建
- [prepare-openwrt.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/prepare-openwrt.sh)：准备 OpenWrt 源码树
- [package-preflight.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/package-preflight.sh)：预编译自定义包
- [ci-smoke.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/ci-smoke.sh)：仓库级静态冒烟检查
- [serial-capture.ps1](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/serial-capture.ps1)：串口日志抓取

## 许可

仓库当前声明为 MIT，具体以各包内文件头与后续补充的 LICENSE 信息为准。
