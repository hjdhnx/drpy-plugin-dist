# drpy-plugin-dist

drpy-node (drpyS) 插件市场官方分发仓库：内置二进制插件（req-proxy / pvideo / pup-sniffer / mediaProxy）的打包发行。

## 使用方式

在 drpy-node 后台管理「插件管理 → 插件市场 → 市场源」中添加本仓库的市场源：

```
https://raw.githubusercontent.com/hjdhnx/drpy-plugin-dist/main/market.json
```

保存后即可在市场页浏览并一键安装。GitHub 访问不畅时，可在同一面板配置「GitHub 加速代理」（如 `https://github.catvod.com/`），安装器会自动兜底重试。

## 插件包规范

每个 zip 为 drpy-node 插件市场规范包（形态 A）：根级含 `plugin.json`（name/version/runtime/binaries 等 manifest）+ 各平台二进制文件。安装器会剥壳落位到 `plugins/<name>/`、校验 sha256、补齐执行权限并登记进 `.plugins.js`。

| 插件 | 说明 | 默认参数 | 平台 |
|---|---|---|---|
| req-proxy | 请求代理服务 | `-p 57571` | win / linux / android |
| pvideo | 嗷呜视频适配代理 | `-port 57572 -dns 8.8.8.8` | win / linux / android |
| pup-sniffer | drplayer 嗅探服务 | `-port 57573` | win / linux |
| mediaProxy | Go 媒体代理服务 | `-port 57574` | win / linux / android |
| captcha-bypass | ddddocr 验证码识别服务（OCR/滑块/旋转，端口 7788，包体约 380MB，x64） | env `PORT=7788` | win / linux (x64) |

### captcha-bypass 组装说明（上游资产再打包）

上游 Hiram-Wong/captcha-bypass 以「每平台散装二进制 + 独立 models.zip」发布，不符合 drpyS 插件包规范，由 `prepare-captcha-bypass.sh` 组装后再走 `release.sh` 发布：

```bash
./prepare-captcha-bypass.sh 1.1.0   # 拉上游资产 -> 组装本地插件目录（含模型/ort-wasm 引导释放）
./release.sh captcha-bypass 1.1.0   # 打包 + 更新 market.json + 发布 release
```

脚本处理了三个上游坑：模型文件名与内置默认路径不同步（`ocr_ppv5-cn.*` vs 内置默认 `ocr_pp.*`，需复制补齐，否则启动报误导性的 wasm 解析错误）；onnxruntime 首启需释放 `ort-wasm/`（Windows 上释放不可靠且 0 字节残骸会导致永久失败，脚本引导运行重试后随包预置）；释放产生的 `logs/` 不进包。大体积 zip（>100MB）通过 .gitignore 豁免入库，仅作为 release asset 分发。

## 版本发布 / 更新插件

### 方式一：一键脚本（推荐）

前提：本仓库 clone 到本地且目录内执行；`gh auth login` 已完成；`plugins/<name>/` 为待发布的插件目录（含二进制，建议含 plugin.json——从市场安装过的就有）。

```bash
./release.sh <插件名> <版本号> [本地插件目录]
# 例：./release.sh req-proxy 1.0.2
```

脚本自动完成：打包 zip（以本地 plugin.json 为基，version 覆盖为发布版本）→ 计算 sha256 → 更新 `market.json`（新插件会自动生成清单条目）→ git commit/push → 创建 release（tag 约定 `<插件名>-v<版本号>`）。

发布后用户端：市场页点「刷新」（或等 60s 缓存过期）→ 该插件卡片出现「更新到 v<版本>」黄色按钮 → 点击即自动"停止旧进程 → 覆盖安装（保留用户 params/env/active）→ 按原状态重启"，全程进度条可视化。

### 方式二：手动步骤

1. 打包：`dist/<插件名>-<版本>.zip`，zip 根级放 `plugin.json`（version 填新版本）+ 各平台二进制；
2. 计算 sha256，更新根目录 `market.json` 对应条目的 `version` / `download`（指向新 release asset）/ `sha256` / `updated`；
3. `git commit && git push`；
4. `gh release create <插件名>-v<版本> dist/<包名>.zip`（tag 约定 `<插件名>-v<版本号>`，download URL 必须与 tag 一致）。

### 注意事项

- 发布后用户端可能短暂（1-5 分钟）仍显示旧版本：raw.githubusercontent.com 的 CDN 缓存所致，客户端已带 cache-buster 参数缓解，仍滞后时稍后手动「刷新」即可；
- `download` 必须是 `github.com/.../releases/download/...` 形态（客户端的 ghProxy 加速兜底只对该域名生效）；
- 版本号建议 semver；市场用数值逐段比较（1.0.2 > 1.0.10 为假，注意 1.0.10 > 1.0.9 才对——逐段数值比较符合直觉）。
