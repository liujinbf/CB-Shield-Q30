# 远程半自动构建

如果你不想每次手工在 `openwrt.ai` 页面里上传、提交、下载、校验，可以使用半自动脚本。

## 前置条件

需要你从浏览器 DevTools 里准备两项信息：

- `Cookie` 请求头
- 上传接口 nonce，也就是 `upload_file` 用到的 `security` 值

如果 overlay 已经上传过，也可以直接提供远端 `files_path`，这样就不需要上传 nonce。

建议把 Cookie 头保存到一个本地文本文件，例如：

```text
.work/openwrt.ai.cookie.txt
```

## PowerShell 用法

首次上传并构建：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 buildremote `
  -CookieHeader "你的完整Cookie头" `
  -UploadNonce "你的上传nonce" `
  -ProfilePath profiles/openwrtai-jcg-q30-pro-passwall.json `
  -VerifyAfterBuild
```

复用已上传 overlay：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 buildremote `
  -CookieFile .work/openwrt.ai.cookie.txt `
  -RemoteOverlayPath "liujinbf/cbshield-openwrtai-overlay.tgz" `
  -ProfilePath profiles/openwrtai-jcg-q30-pro-openclash.json `
  -VerifyAfterBuild
```

## Python 直接调用

```bash
python scripts/openwrtai-build.py \
  --cookie-file .work/openwrt.ai.cookie.txt \
  --upload-nonce "你的上传nonce" \
  --profile profiles/openwrtai-jcg-q30-pro.json \
  --defaults-inline \
  --verify
```

## 脚本做的事情

1. 上传本地 overlay，或复用远端 `files_path`
2. 生成构建请求并提交到 `openwrt.ai`
3. 轮询构建状态直到成功
4. 下载 `sysupgrade` 固件到 `.work/`
5. 可选执行本地镜像校验
