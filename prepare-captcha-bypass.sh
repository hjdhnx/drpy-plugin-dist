#!/usr/bin/env bash
# captcha-bypass（ddddocr 验证码识别）上游资产组装脚本
# 上游以「每平台散装二进制 + 独立 models.zip」发布，不符合 drpyS 插件包规范（单 zip + plugin.json），
# 本脚本负责拉取上游 release 并组装成标准插件目录，打包/发布继续用 release.sh。
#
# 用法: ./prepare-captcha-bypass.sh [版本号] [插件输出目录]
#   例: ./prepare-captcha-bypass.sh 1.1.0
# 流程: gh release download 上游资产 -> 组装 plugin.json + 重命名二进制 + models/ + public/ + LICENSE
# 前置: gh auth login；python3（解压用）。
set -euo pipefail

VERSION=${1:-1.1.0}
OUT=${2:-/e/gitwork/drpy-node/plugins/captcha-bypass}
UPSTREAM_REPO="Hiram-Wong/captcha-bypass"
UPSTREAM_TAG="v${VERSION}"
CACHE="build/captcha-bypass-cache"

[ -f market.json ] || { echo "✗ 请在本仓库根目录执行"; exit 1; }

echo "==> 下载上游 ${UPSTREAM_REPO} ${UPSTREAM_TAG} 资产（缓存目录 ${CACHE}，已存在的资产自动跳过）"
mkdir -p "$CACHE"
cd "$CACHE"
for f in captcha-bypass-server-win-x64.exe captcha-bypass-server-linux-x64 models.zip public.zip; do
  if [ -f "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    echo "    跳过（已缓存）: $f"
  else
    rm -f "$f"
    gh release download "$UPSTREAM_TAG" --repo "$UPSTREAM_REPO" -p "$f" --clobber
  fi
done

echo "==> 组装插件目录 ${OUT}"
# Windows python 不认 Git Bash 的 /e/... 路径，统一转成 E:/... 形式（cp 等 bash 工具同样兼容）
OUT=$(cygpath -m "$OUT")
# 完全重建，避免历史运行残留（如 ort 运行时释放的 ort-wasm/）混进发布包
rm -rf "$OUT"
mkdir -p "$OUT"
cp -f captcha-bypass-server-win-x64.exe "$OUT/captcha-bypass-win.exe"
cp -f captcha-bypass-server-linux-x64  "$OUT/captcha-bypass-linux"
rm -rf "$OUT/models" "$OUT/public"
# 两个 zip 自带 models/、public/ 顶层目录，直接解压到插件根
python -c "import zipfile; zipfile.ZipFile('models.zip').extractall('$OUT')"
python -c "import zipfile; zipfile.ZipFile('public.zip').extractall('$OUT')"

# 上游资产不同步补丁：v1.1.0 起内置默认模型路径为 models/ocr_pp.onnx(.json)，
# 而 models.zip 内的文件名是 ocr_ppv5-cn.*，缺文件会导致 server 启动报
# "WebAssembly.Module doesn't parse at byte 0"（误导性报错，实际是模型路径 404）。
# 复制一份为默认名，打补丁后需在上游修复该问题时移除。
cp -f "$OUT/models/ocr_ppv5-cn.onnx" "$OUT/models/ocr_pp.onnx"
cp -f "$OUT/models/ocr_ppv5-cn.json" "$OUT/models/ocr_pp.json"
# 上游 MIT 许可随包分发
gh api "repos/${UPSTREAM_REPO}/contents/LICENSE" --jq '.content' | python -c "import sys,base64;sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" > "$OUT/LICENSE"

cat > "$OUT/plugin.json" <<EOF
{
  "name": "captcha-bypass",
  "version": "${VERSION}",
  "title": "验证码识别服务 (ddddocr)",
  "desc": "ddddocr-node 二进制版：OCR 文字/算术、滑块、旋转验证码识别，HTTP API 默认 7788 端口（env PORT 可改）。包体约 300MB，模型加载后常驻内存约 300-500MB，低配设备慎用。接口：POST /captcha/ocr|detect|rotate|slide，GET /health。上游：Hiram-Wong/captcha-bypass (MIT)",
  "author": "Hiram-Wong",
  "runtime": "binary",
  "params": "",
  "env": { "PORT": "7788" },
  "binaries": {
    "win32": "captcha-bypass-win.exe",
    "linux": "captcha-bypass-linux"
  },
  "homepage": "https://github.com/Hiram-Wong/captcha-bypass",
  "_source": "drpy-plugin-dist"
}
EOF

echo "==> 引导运行：释放 ort-wasm 运行时资产（Windows 上释放不可靠且失败会残留 0 字节文件，需重试）"
# onnxruntime 首启需解出 ort-wasm/ort-wasm-simd-threaded.wasm（约13MB）到二进制旁。
# 释放动作与杀软扫描存在竞争，可能截断为 0 字节；且 ort 检测到文件已存在就不重写，
# 之后每次启动都会读到 0 字节报 "WebAssembly.Module doesn't parse at byte 0"。
# 故每次尝试前先清除残骸，循环重试直至释放完整并健康检查通过，随后随包分发。
OK=0
for attempt in 1 2 3 4 5; do
  rm -rf "$OUT/ort-wasm"
  PORT=7789 "$OUT/captcha-bypass-win.exe" > boot.log 2>&1 &
  BOOT_PID=$!
  for i in $(seq 1 30); do
    sleep 2
    if curl -sf -m 3 "http://127.0.0.1:7789/health" >/dev/null 2>&1; then OK=1; break; fi
  done
  kill $BOOT_PID 2>/dev/null || true
  taskkill //IM captcha-bypass-win.exe //F >/dev/null 2>&1 || true
  if [ "$OK" = "1" ]; then break; fi
  echo "    第 ${attempt} 次引导失败，重试…"
  sleep 2
done
[ "$OK" = "1" ] || { echo "✗ 引导运行失败（已重试 5 次），见 $PWD/boot.log"; exit 1; }
[ -s "$OUT/ort-wasm/ort-wasm-simd-threaded.wasm" ] || { echo "✗ ort-wasm 未释放成功"; exit 1; }
echo "    ort-wasm 释放完成: $(stat -c%s "$OUT/ort-wasm/ort-wasm-simd-threaded.wasm") bytes"
# 引导运行产生的日志目录不进包
rm -rf "$OUT/logs"

echo "✓ 组装完成: $OUT"
echo "  下一步: ./release.sh captcha-bypass ${VERSION}"
