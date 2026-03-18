# WSL2 编译入口

如果你在 Windows 上开发，推荐直接用 WSL2 Ubuntu 执行本仓库的自编链路。

## 前提

需要先准备好：

1. Windows 已启用 WSL2
2. 已安装 Ubuntu 发行版
3. Ubuntu 里已安装 OpenWrt 常用编译依赖

## 直接从 PowerShell 调用

编译稳定版：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action build -Profile stable
```

安装 WSL 依赖：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action bootstrap -Distro Ubuntu
```

只做准备和预检：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action prepare -Profile stable
```

打开仓库对应的 WSL shell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action shell
```

如果你的 WSL 发行版名字不是 `Ubuntu`，可以指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action build -Distro Ubuntu-22.04
```

## 说明

[wsl-build.ps1](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/wsl-build.ps1) 会自动把当前 Windows 仓库路径转换成 WSL 路径，例如：

- `D:\下载\CB-Shield-Q30\CB-Shield-Q30`
- 转成 `/mnt/d/下载/CB-Shield-Q30/CB-Shield-Q30`

这样你不需要手工切路径或重新拼命令。

如果当前机器还没装 Ubuntu，先看 [wsl-setup.md](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/docs/wsl-setup.md)。
