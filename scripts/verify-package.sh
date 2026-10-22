#!/usr/bin/env bash
# 校验 payload 与某处的同名文件是否一致。
#
#   verify-package.sh --source          # 维护用：payload 是否落后于仓库根
#   verify-package.sh --target /repo    # 使用方：目标仓库是否被本地改过
#
# 退出码：0 全部一致 / 1 有不一致 / 2 有缺失 / 3 用法错误
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD="$PKG/payload"
LIST="$PKG/payload.manifest.txt"

MODE=""
BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) MODE="source"; BASE="$(cd "$PKG/../../.." 2>/dev/null && pwd || true)" ;;
    --repo) MODE="source"; BASE="${2:-}"; shift ;;
    --target) MODE="target"; BASE="${2:-}"; shift ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 3 ;;
  esac
  shift
done

[ -n "$MODE" ] || { echo "需要 --source 或 --target <dir>" >&2; exit 3; }
[ -d "$BASE" ] || { echo "目录不存在: ${BASE:-空}。发布仓库里请用 --repo <治理仓库根>" >&2; exit 3; }
if [ "$MODE" = "source" ] && [ ! -f "$BASE/scripts/quality_gate.py" ]; then
  echo "$BASE 不是治理仓库根（缺 scripts/quality_gate.py）；请用 --repo 指定" >&2; exit 3
fi

same=0; diff=0; missing=0
for rel in $(cat "$LIST"); do
  p="$PAYLOAD/$rel"; b="$BASE/$rel"
  if [ ! -f "$p" ]; then
    printf '  payload缺  %s\n' "$rel"; diff=$((diff+1)); continue
  fi
  if [ ! -f "$b" ]; then
    printf '  目标缺     %s\n' "$rel"; missing=$((missing+1)); continue
  fi
  if cmp -s "$p" "$b"; then
    same=$((same+1))
  elif { [ "$rel" = "AGENTS.md" ] || [ "$rel" = "CONTRIBUTING.md" ]; } && grep -q 'CSDD:BEGIN' "$b"; then
    # 这两个文件按“带标记追加”安装，整份必然与 payload 不同；有标记即视为已安装
    same=$((same+1))
  else
    printf '  不一致     %s\n' "$rel"; diff=$((diff+1))
  fi
done

echo ""
echo "模式=$MODE 基目录=$BASE"
echo "一致 $same / 不一致 $diff / 目标缺失 $missing"

if [ "$missing" -gt 0 ]; then exit 2; fi
if [ "$diff" -gt 0 ]; then exit 1; fi
echo "全部一致。"
