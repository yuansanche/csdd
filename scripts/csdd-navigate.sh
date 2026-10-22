#!/usr/bin/env bash
# 新增模块前的导航：把已装的 Blueprint Index 与 BrownKit 的确定性脚本输出汇总给人或 agent 看。
# 只读，不写文件；缺哪个扩展就跳过哪段并说明。
#
#   csdd-navigate.sh [--target /repo]
set -uo pipefail

TARGET="."
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "目标目录不存在" >&2; exit 1; }
cd "$TARGET"

EXT=".specify/extensions"
echo "== 1 架构地图状态（Blueprint Index）"
BS="$EXT/blueprint-index/scripts/bash/blueprint-state.sh"
if [ ! -f "$BS" ]; then
  echo "  未安装 blueprint-index（csdd-extensions.sh --install blueprint-index）"
elif [ ! -f .specify/memory/blueprint.md ]; then
  echo "  已安装但还没有地图。先在 agent 里运行 /speckit.blueprint-index.init --from-code"
elif ! { [ "${BASH_VERSINFO[0]}" -gt 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 5 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }; }; then
  echo "  当前 bash ${BASH_VERSION} 跑不了 check（需要 >= 5.2），跳过。"
else
  bash "$BS" check --human || true
fi

echo
echo "== 2 技术栈与清单（BrownKit 确定性脚本）"
BK="$EXT/brownkit/scripts/bash"
if [ -f "$BK/detect-stack.sh" ]; then
  # detect_stack.py 不忽略 .specify/.claude/.agents，会把第三方扩展自带文件算成项目语言；
  # 先复制一份排除这些目录的副本再检测（项目很大时会慢；root 字段会显示临时目录）
  STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
  tar --exclude=./.git --exclude=./.specify --exclude=./.claude --exclude=./.agents \
      --exclude=./node_modules --exclude=./.venv --exclude=./reports -cf - . | tar -C "$STAGE" -xf -
  STACK="$(bash "$BK/detect-stack.sh" --root "$STAGE" 2>&1 || true)"
  printf '%s\n' "$STACK" | sed -n '1,45p'
else
  echo "  未安装 brownkit（csdd-extensions.sh --install brownkit）"
fi

echo
echo "== 3 接下来由你或 agent 完成（本脚本不替你判断）"
echo "  a. 在上面列出的模块里找职责相近的现有实现，不要只凭文件名。"
echo "  b. 记录复用检查结论：直接复用 / 配置 / 适配 / 无满足条件，并写明依据。"
echo "  c. 若要改已有功能，先找出实际被入口调用的那个实现，证据不足就写“未知”。"
