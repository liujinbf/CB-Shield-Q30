# Kwrt 运行时叠加流程

这条流程用于绕开当前 `factory.bin` 在不死 U-Boot 恢复页上的兼容问题。

核心思路：

1. 先刷已经验证能正常启动的 `Kwrt/openwrt.ai` Q30 固件
2. 确认路由器已经能正常获取管理地址、进入 LuCI、发射 Wi-Fi
3. 再把本仓库产出的 `CB-Shield` 运行时叠加包安装到这套可运行系统上

## 产物生成

Linux / WSL / Git Bash：

```bash
bash scripts/build-kwrt-runtime-bundle.sh
```

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\kwrt-runtime.ps1 build
```

生成后会得到：

- `.work/cbshield-kwrt-runtime.tgz`
- `.work/cbshield-kwrt-install.sh`
- `.work/kwrt-runtime.manifest`
- `.work/cbshield-kwrt-runtime-bundle.tgz`

## 路由器端安装

先把下面两个文件上传到路由器，例如放到 `/tmp/`：

- `.work/cbshield-kwrt-runtime.tgz`
- `.work/cbshield-kwrt-install.sh`

然后通过 SSH 执行：

```sh
chmod +x /tmp/cbshield-kwrt-install.sh
sh /tmp/cbshield-kwrt-install.sh /tmp/cbshield-kwrt-runtime.tgz
```

## 安装脚本会做什么

- 检查基础命令是否存在
- 自动安装缺少的运行依赖，例如 `curl`、`jsonfilter`、`uhttpd`
- 备份将被覆盖的现有文件到 `/etc/cbshield/runtime-backup-时间戳/`
- 解压 CB-Shield 叠加文件到系统根目录
- 执行主题和首启 defaults
- 清理 LuCI 缓存
- 后台重载 `network`、`wifi`、`rpcd`、`uhttpd`

## 安装后的预期结果

- 管理地址切换为 `192.168.10.1`
- LuCI 首页切到 `admin/cbshield/dashboard`
- 出现 `CB-Shield-Office` 与 `CB-Shield-Office-5G`
- `cb-riskcontrol`、`cb-healthcheck`、`cb-ha-monitor`、`cb-dns-guard`、`cb-portal` 已启用

## 建议验收

1. 访问 `http://192.168.10.1/`
2. 执行 `opkg list-installed | grep -E 'curl|jsonfilter|uhttpd|luci'`
3. 执行 `ps | grep -E 'cb-riskcontrol|uhttpd'`
4. 执行 `uci show wireless | grep office_`
5. 查看 `/tmp/cbshield-runtime-restart.log`

## 这条路线的边界

它解决的是：

- 启动兼容问题
- LuCI 业务页面叠加
- 运维脚本与 Portal 上线
- 默认网络与 Wi-Fi 策略落地

它不解决的是：

- 底层 DTS / 分区 / bootloader 修改
- 自定义内核模块编译
- 首次刷机必须使用我们自编 `factory.bin`
