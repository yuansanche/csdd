#!/usr/bin/env bash
# 把仓库根下的治理文件同步到 payload/。
# 只在维护本包时运行；安装时只读 payload，不读仓库根。
#
#   sync-payload.sh [--repo /path/to/governance-repo]
# 默认源仓库是本包上三级（本包位于 <repo>/.specify/packages/csdd 时成立）；
# 本包被单独克隆（发布仓库）时，必须用 --repo 指向治理文件所在的仓库根。
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift ;;
    -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done
if [ -z "$REPO" ]; then
  REPO="$(cd "$PKG/../../.." 2>/dev/null && pwd || true)"
  [ -f "$REPO/scripts/quality_gate.py" ] || { echo "默认路径 ${REPO:-?} 不是治理仓库根；请用 --repo 指定" >&2; exit 1; }
fi
[ -f "$REPO/scripts/quality_gate.py" ] || { echo "--repo 不是治理仓库根（缺 scripts/quality_gate.py）: $REPO" >&2; exit 1; }
REPO="$(cd "$REPO" && pwd)"
PAYLOAD="$PKG/payload"
LIST="$PKG/payload.manifest.txt"

[ -f "$LIST" ] || { echo "缺少 payload.manifest.txt" >&2; exit 1; }

mkdir -p "$PAYLOAD"
added=0; updated=0

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in \#*) continue ;; esac
  src="$REPO/$rel"
  dst="$PAYLOAD/$rel"
  if [ ! -f "$src" ]; then
    echo "  缺源  $rel" >&2
    exit 2
  fi
  mkdir -p "$(dirname "$dst")"
  if [ ! -f "$dst" ]; then
    cp "$src" "$dst"; added=$((added+1))
  elif ! cmp -s "$src" "$dst"; then
    cp "$src" "$dst"; updated=$((updated+1))
  fi
done < "$LIST"

# 清掉 payload 里已不在清单中的文件
removed=0
while IFS= read -r f; do
  rel="${f#"$PAYLOAD"/}"
  if ! grep -qxF "$rel" "$LIST"; then
    rm -f "$f"; removed=$((removed+1))
  fi
done < <(find "$PAYLOAD" -type f)

find "$PAYLOAD" -type d -empty -delete 2>/dev/null || true

echo "payload 同步完成：新增 ${added}，更新 ${updated}，移除 $removed"
echo "文件数：$(find "$PAYLOAD" -type f | wc -l | tr -d ' ')"
