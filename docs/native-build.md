# 自行编译说明

当前仓库仍然保留完整的自编链路，核心入口如下：

- [prepare-openwrt.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/prepare-openwrt.sh)
- [local-build.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/local-build.sh)
- [build-stable.yml](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/.github/workflows/build-stable.yml)

## 结论

可以继续自行编译，并且对 `JCG Q30 PRO` 来说，目前比 `openwrt.ai` 自定义 `factory` 更稳。

但注意：

- 不支持 Windows 原生 `PowerShell + Git Bash` 直接编译
- 推荐环境：
  - Ubuntu / Debian
  - WSL2 Ubuntu
  - GitHub Actions

## 本地构建

在 Linux / WSL2 中执行：

```bash
bash scripts/local-build.sh stable
```

产物输出到：

- `artifacts/stable`

如果你当前在 Windows 上，推荐直接用 [wsl-build.ps1](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/wsl-build.ps1)：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wsl-build.ps1 -Action build -Profile stable
```

详细说明见：

- [wsl-build.md](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/docs/wsl-build.md)
- [wsl-setup.md](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/docs/wsl-setup.md)

## 只做准备

```bash
bash scripts/prepare-openwrt.sh /path/to/openwrt stable
bash scripts/package-preflight.sh /path/to/openwrt
```

## 当前 Windows 环境的限制

这次实际验证里，当前 Windows 桌面环境在 `scripts/feeds` 阶段直接报错：

- 找不到 `make`
- `scripts/feeds` 无法继续

所以如果你在当前机器上继续自编，必须先切到：

1. WSL2 Ubuntu
2. 一台 Linux 主机
3. 或直接用 GitHub Actions

## 已补充的保护

现在自编入口已经前置环境检查：

- [check-build-env.sh](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/check-build-env.sh)

如果在不支持的环境里执行，会直接报错退出，而不是跑到中途才失败。
