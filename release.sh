#!/usr/bin/env bash
# drpy-plugin-dist 插件发布脚本
# 用法: ./release.sh <插件名> <版本号> [本地插件目录]
#   例: ./release.sh req-proxy 1.0.2
# 前置: 本地插件目录 plugins/<name>/ 存在（推荐已含 plugin.json，可从市场安装获得）；
#       已 gh auth login；本仓库已 clone 并位于当前目录。
# 依赖: python3, git, gh
set -euo pipefail

NAME=${1:?用法: ./release.sh <插件名> <版本号> [本地插件目录]}
VERSION=${2:?用法: ./release.sh <插件名> <版本号> [本地插件目录]}
LOCAL_PLUGINS=${3:-E:/gitwork/drpy-node/plugins}
SRC="$LOCAL_PLUGINS/$NAME"
ZPATH="dist/${NAME}-${VERSION}.zip"

[ -d "$SRC" ] || { echo "✗ 本地插件目录不存在: $SRC"; exit 1; }
[ -f market.json ] || { echo "✗ 请在本仓库根目录执行"; exit 1; }

echo "==> 打包 $NAME v$VERSION"
HASH=$(python - "$NAME" "$VERSION" "$SRC" "$ZPATH" <<'PY'
import zipfile, json, hashlib, os, sys
name, version, src, zpath = sys.argv[1:5]
mp = os.path.join(src, 'plugin.json')
manifest = json.load(open(mp, encoding='utf-8')) if os.path.exists(mp) else {}
manifest.update({'name': name, 'version': version, 'runtime': manifest.get('runtime', 'binary')})
files = sorted(f for f in os.listdir(src) if os.path.isfile(os.path.join(src, f)) and f != 'plugin.json')
with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('plugin.json', json.dumps(manifest, ensure_ascii=False, indent=2))
    for f in files:
        z.write(os.path.join(src, f), f)
h = hashlib.sha256(open(zpath, 'rb').read()).hexdigest()
print(h, len(files))
PY
)
HASH=$(echo "$HASH" | awk '{print $1}')
echo "    $ZPATH  sha256=${HASH:0:16}..."

echo "==> 更新 market.json"
python - "$NAME" "$VERSION" "$HASH" <<'PY'
import json, sys, datetime
name, version, sha = sys.argv[1:4]
m = json.load(open('market.json', encoding='utf-8'))
entry = next((e for e in m['plugins'] if e['name'] == name), None)
download = f"https://github.com/hjdhnx/drpy-plugin-dist/releases/download/v{version}/{name}-{version}.zip"
if entry:
    entry.update(version=version, download=download, sha256=sha)
else:  # 新插件上架：从包内 manifest 生成清单条目
    import zipfile
    with zipfile.ZipFile(f"dist/{name}-{version}.zip") as z:
        mf = json.loads(z.read('plugin.json'))
    platforms = sorted(set(mf.get('binaries', {k: '' for k in ()}).keys())) or ['win32']
    entry = {
        "name": name, "version": version, "title": mf.get('title', name), "desc": mf.get('desc', ''),
        "author": mf.get('author', 'hjdhnx'), "runtime": mf.get('runtime', 'binary'),
        "entry": mf.get('entry', 'index.js'), "params": mf.get('params', ''), "env": mf.get('env', {}),
        "platforms": platforms, "download": download, "sha256": sha,
        "homepage": mf.get('homepage', '')
    }
    m['plugins'].append(entry)
m['updated'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
json.dump(m, open('market.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('    清单已更新:', [(e['name'], e['version']) for e in m['plugins']])
PY

echo "==> 提交推送 + 发布 release v$VERSION"
git add -A
git commit -q -m "release: ${NAME} v${VERSION}" || echo "    (无变更需要提交)"
git push -q origin main
gh release create "v${VERSION}" "$ZPATH" --title "${NAME} v${VERSION}" --notes "${NAME} 发布 ${VERSION}。" >/dev/null
echo "✓ 发布完成: https://github.com/hjdhnx/drpy-plugin-dist/releases/tag/v${VERSION}"
