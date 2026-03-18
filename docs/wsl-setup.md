# WSL2 Ubuntu 最短安装流程

目标：让当前这台 Windows 机器具备 OpenWrt 自编环境。

## 1. 安装 WSL2 Ubuntu

管理员 PowerShell 执行：

```powershell
wsl --install -d Ubuntu
```

安装完成后重启系统。

如果系统里已经有 WSL，但没有 Ubuntu，也可以执行：

```powershell
wsl --list --online
wsl --install -d Ubuntu-22.04
```

## 2. 首次进入 Ubuntu

```powershell
wsl -d Ubuntu
```

按提示创建 Linux 用户名和密码，然后退出。

## 3. 安装编译依赖

回到仓库目录后执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action bootstrap -Distro Ubuntu
```

如果你的发行版名不是 `Ubuntu`，把 `-Distro` 改成实际名称，例如：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action bootstrap -Distro Ubuntu-22.04
```

## 4. 预准备 OpenWrt 树

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action prepare -Profile stable -Distro Ubuntu
```

## 5. 开始编译

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action build -Profile stable -Distro Ubuntu
```

## 6. 产物位置

编译完成后查看：

- `artifacts/stable`

## 补充

- [wsl-build.ps1](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/wsl-build.ps1) 是 Windows 侧入口
- [wsl-bootstrap.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/wsl-bootstrap.sh) 负责在 Ubuntu 里安装依赖
- [native-build.md](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/docs/native-build.md) 是总体自编说明
