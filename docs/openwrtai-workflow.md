# openwrt.ai 工作流

这套流程用于替代本地整包源码编译。日常迭代只维护覆盖包、`defaults` 和静态检查，最终固件交给 `openwrt.ai` 会员功能构建。

## 一键准备

```bash
bash scripts/prepare-openwrtai-upload.sh
```

PowerShell 环境可直接执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 prepare
```

产物会生成到 `.work/`：

- `cbshield-openwrtai-overlay.tgz`
- `cbshield-openwrtai-defaults.sh`
- `openwrtai-overlay.manifest`

## 单独命令

生成覆盖包：

```bash
bash scripts/build-openwrtai-overlay.sh
```

PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 overlay
```

生成网站 `defaults` 内容：

```bash
bash scripts/render-openwrtai-defaults.sh
```

PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 defaults
```

直接输出到终端，方便粘贴：

```bash
bash scripts/render-openwrtai-defaults.sh --stdout
```

校验下载回来的 `sysupgrade` 固件：

```bash
python scripts/verify-openwrtai-image.py /path/to/sysupgrade.bin
```

PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 verify -ImagePath .\.work\xxx-sysupgrade.bin
```

渲染网站参数模板：

```bash
python scripts/render-openwrtai-request.py --format summary
python scripts/render-openwrtai-request.py --format json --overlay liujinbf/cbshield-openwrtai-overlay.tgz --defaults-inline
```

PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 request
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 request -ProfilePath profiles/openwrtai-jcg-q30-pro-passwall.json
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 request -RequestFormat checklist -ProfilePath profiles/openwrtai-jcg-q30-pro-openclash.json
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 acceptance
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 buildremote -CookieHeader "..." -UploadNonce "..."
```

如果缺少 Python 依赖，先执行：

```bash
python -m pip install PySquashfsImage
```

## 网站侧建议

推荐在 `openwrt.ai` 里使用：

- 机型：`JCG Q30 PRO`
- 主题：`Argon`
- Web 服务器：`Nginx`
- 文件系统：`squashfs`
- 自定义文件包：上传 `.work/cbshield-openwrtai-overlay.tgz`
- `defaults`：粘贴 `.work/cbshield-openwrtai-defaults.sh`

额外包至少建议补齐：

- `curl`
- `ca-bundle`
- `ca-certificates`

如果需要代理能力，再按需勾选：

- `Passwall`
- `OpenClash`

网站模板文件见 [openwrtai-jcg-q30-pro.json](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/profiles/openwrtai-jcg-q30-pro.json)。

如果你要固定代理方案，可直接选：

- [openwrtai-jcg-q30-pro-passwall.json](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/profiles/openwrtai-jcg-q30-pro-passwall.json)
- [openwrtai-jcg-q30-pro-openclash.json](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/profiles/openwrtai-jcg-q30-pro-openclash.json)

半自动远程构建说明见 [remote-build.md](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/docs/remote-build.md)。

## 能力边界

这套流程适合：

- LuCI 控制器、模板、静态资源
- `/etc/config`、`/etc/init.d`、`/usr/bin` 脚本
- Portal 页面
- 首启默认配置

这套流程不负责：

- DTS、分区、内核、驱动级修改
- feed 源码 patch
- 必须重新编译的原生二进制包
