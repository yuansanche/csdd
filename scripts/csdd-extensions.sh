#!/usr/bin/env bash
# 按清单管理第三方扩展。默认不安装任何组件。
#
#   csdd-extensions.sh --list
#   csdd-extensions.sh --install <id> [--target /repo]
#
# 硬规则：source 或 sha256 缺失 → 拒绝安装。不做版本漂移的静默安装。
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$PKG/extensions.manifest.json"
PY=""
for c in python3.11 python3; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -n "$PY" ] || { echo "需要 python3" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "缺少 extensions.manifest.json" >&2; exit 1; }

ACTION=""
ID=""
TARGET="."

while [ $# -gt 0 ]; do
  case "$1" in
    --list) ACTION="list" ;;
    --install) ACTION="install"; ID="${2:-}"; shift ;;
    --target) TARGET="${2:-}"; shift ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done

field() {
  "$PY" - "$MANIFEST" "$1" "$2" <<'PY'
import json,sys
m,i,k=sys.argv[1],sys.argv[2],sys.argv[3]
for c in json.load(open(m,encoding="utf-8"))["components"]:
    if c["id"]==i:
        v=c.get(k)
        if isinstance(v,list): v=",".join(str(x) for x in v)
        print("" if v is None else v)
        break
else:
    raise SystemExit(3)
PY
}

if [ "$ACTION" = "list" ]; then
  "$PY" - "$MANIFEST" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
print(d["policy"]["rule"])
print()
print(f'{"id":20}{"ver":16}{"kind":20}{"sha256":8}{"建议":6}')
for c in d["components"]:
    sha="有" if c.get("sha256") else "缺"
    print(f'{c["id"]:20}{c["version"]:16}{c["kind"]:20}{sha:8}{c.get("recommendation",""):6}')
print()
print("缺失 sha256 的组件无法安装。补哈希后再用 --install。")
PY
  exit 0
fi

[ "$ACTION" = "install" ] || { echo "需要 --list 或 --install <id>" >&2; exit 1; }
[ -n "$ID" ] || { echo "缺少组件 id" >&2; exit 1; }

KIND="$(field "$ID" kind || true)"
if [ -z "$KIND" ]; then
  echo "清单里没有组件: $ID（用 --list 查看可安装的 id）" >&2
  exit 1
fi
SRC="$(field "$ID" source)"
SHA="$(field "$ID" sha256)"
HINT="$(field "$ID" manual_hint)"

if [ "$KIND" != "spec-kit-extension" ]; then
  echo "组件 $ID 的类型是 ${KIND}，本脚本不代管。"
  [ -n "$HINT" ] && echo "人工处理建议：$HINT"
  exit 1
fi

case "$SRC" in https://*) ;; *)
  echo "拒绝安装 ${ID}：source 缺失或不是 https 地址（当前: ${SRC:-空}）。"
  [ -n "$HINT" ] && echo "提示：$HINT"
  exit 1 ;;
esac
if ! printf '%s' "$SHA" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "拒绝安装 ${ID}：sha256 缺失或不是 64 位十六进制，无法固定版本。"
  [ -n "$HINT" ] && echo "提示：$HINT"
  exit 1
fi
SID="$(field "$ID" speckit_id)"
INCLUDE="$(field "$ID" include)"
YML_SHA="$(field "$ID" audited_extension_yml_sha256)"
TREE_SHA="$(field "$ID" tree_sha256)"
[ -n "$SID" ] || { echo "清单缺少 speckit_id: $ID" >&2; exit 1; }
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "目标目录不存在" >&2; exit 1; }
if [ ! -f "$TARGET/.specify/integration.json" ] && [ ! -f "$TARGET/.specify/init-options.json" ]; then
  echo "目标未初始化 spec-kit（缺 .specify/integration.json），先 specify init。" >&2
  exit 2
fi

apply_default_hooks() {
  "$PY" - "$MANIFEST" "$ID" <<'PYEOF' | while IFS='|' read -r pt cm md; do
import json, sys
for c in json.load(open(sys.argv[1], encoding="utf-8"))["components"]:
    if c["id"] == sys.argv[2]:
        for h in c.get("default_hooks") or []: print(f'{h["point"]}|{h["command"]}|{h["mode"]}')
PYEOF
    bash "$PKG/scripts/csdd-hooks.sh" --set "$pt" "$cm" "$md" --target "$TARGET" || echo "  默认钩子 $pt/$cm 未能设置（可用 /speckit.csdd.hooks 手动设）" >&2
  done
}

# 已装则不重复安装（specify extension add 会拒绝），只补默认钩子，保证重复运行幂等
SPEC0=(uvx --from "specify-cli==1.1.3" specify)
if command -v specify >/dev/null 2>&1 && specify --version 2>&1 | grep -q '1\.1\.3'; then SPEC0=(specify); fi
if (cd "$TARGET" && "${SPEC0[@]}" extension list 2>&1 || true) | grep -Eq "^[[:space:]]+${SID}\$"; then
  echo "${ID} 已安装（spec-kit id: ${SID}），跳过安装，仅确认默认钩子"
  apply_default_hooks
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# 缓存优先：本包 cache/ 里有且哈希与清单一致，就不联网；否则下载 source 并校验整包哈希
MIRROR="$(field "$ID" mirror_file || true)"
MIRROR_SHA="$(field "$ID" mirror_sha256 || true)"
if [ -n "$MIRROR" ] && [ -f "$PKG/$MIRROR" ] && [ "$(sha256_of "$PKG/$MIRROR")" = "$MIRROR_SHA" ]; then
  cp "$PKG/$MIRROR" "$TMP/pkg.zip"
  echo "使用本包缓存 $MIRROR（哈希与清单一致，未联网）"
else
  [ -z "$MIRROR" ] || echo "缓存缺失或哈希不符，改为联网下载（缓存: $MIRROR）"
  echo "下载 $SRC"
  curl -fsSL --retry 3 --retry-all-errors -m 180 -o "$TMP/pkg.zip" "$SRC"
  ACTUAL="$(sha256_of "$TMP/pkg.zip")"
  if [ "$ACTUAL" != "$SHA" ]; then
    echo "哈希不一致，拒绝安装。"
    echo "  期望 $SHA"
    echo "  实际 $ACTUAL"
    exit 1
  fi
  echo "整包哈希校验通过"
fi

DIR="$("$PY" "$PKG/scripts/fetch_extension.py" "$TMP/pkg.zip" "$TMP/x" \
  --include "$INCLUDE" --yml-sha "$YML_SHA" --tree-sha "$TREE_SHA")" \
  || { echo "解压或校验失败，拒绝安装 ${ID}。" >&2; exit 1; }

# 优先用本机已装的 specify 1.1.3；否则用 uvx 固定版本，不用漂移的最新版
if command -v specify >/dev/null 2>&1 && specify --version 2>&1 | grep -q '1\.1\.3'; then
  SPEC=(specify)
else
  SPEC=(uvx --from "specify-cli==1.1.3" specify)
fi

NEEDS_BASH52="$(field "$ID" needs_bash_52 || true)"
if [ "$NEEDS_BASH52" = "True" ] && ! { [ "${BASH_VERSINFO[0]}" -gt 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 5 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }; }; then
  echo "警告: ${ID} 的检查脚本在 bash ${BASH_VERSION} 下语法不通过（实测 bash 5.1.16 与 3.2 失败，5.2.15 通过）。" >&2
  echo "      仍会安装，但运行其 check 前请先用 bash >= 5.2（macOS 用 brew install bash）。" >&2
fi

cd "$TARGET"
# --dev 是本地目录安装：绕过 512 条目上限与 Untrusted Source 确认；来源可信度已由上面的整包哈希承担
echo y | "${SPEC[@]}" extension add "$DIR" --dev
# 先存变量再匹配：pipefail 下 grep -q 提前退出会让上游收到断管，整条管道误报失败
LISTED="$("${SPEC[@]}" extension list 2>&1 || true)"
if ! printf '%s\n' "$LISTED" | grep -Eq "^[[:space:]]+${SID}\$"; then
  echo "安装命令返回了，但 extension list 里没有 ${SID}，视为失败。" >&2
  exit 4
fi
apply_default_hooks
echo ""
echo "已安装 ${ID}（spec-kit id: ${SID}）。注意：安装不等于能力验证。"
