#!/usr/bin/env bash
# csdd-install.sh —— 把 CSDD 治理层安装到一个已初始化 spec-kit 的仓库。
#
# 只读包内 payload/，不读源仓库；因此在 .specify/extensions/csdd/ 下运行效果相同。
# 默认预演；--apply 才写入；冲突默认跳过，--force 才覆盖。
#
# 用法：
#   csdd-install.sh --target /path/to/repo [--agent claude] [--apply] [--force]
#
# 退出码：0 成功 / 1 用法错误 / 2 目标未初始化 / 3 有冲突 / 4 自检失败

set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD="$PKG/payload"
TARGET=""
APPLY=0
FORCE=0
AGENT="claude"

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift ;;
    --agent)  AGENT="${2:-}"; shift ;;
    --apply)  APPLY=1 ;;
    --force)  FORCE=1 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done

[ -n "$TARGET" ] || { echo "需要 --target <dir>" >&2; exit 1; }
[ -d "$TARGET" ] || { echo "目标目录不存在: $TARGET" >&2; exit 1; }
[ -d "$PAYLOAD" ] || { echo "包内缺少 payload/，先运行 scripts/sync-payload.sh" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

say()  { printf '%s\n' "$*"; }
plan() { printf '  %-8s %s\n' "$1" "$2"; }

# 这两个文件通常由项目自己维护，整份覆盖会破坏其指令；改为带标记追加。
APPEND_FILES="AGENTS.md CONTRIBUTING.md"
is_append() { for f in $APPEND_FILES; do [ "$1" = "$f" ] && return 0; done; return 1; }

append_block() {
  case "$1" in
    AGENTS.md) cat <<'EOF'

<!-- CSDD:BEGIN 由 csdd-install.sh 追加，请勿手改本区块 -->
## CSDD 治理入口

本仓库已接入 CSDD 治理层。

- 执行流程与角色：docs/workflow.md
- 门禁规则：docs/quality-gates.md
- 治理原则：.specify/memory/constitution.md
- 自检：python3 scripts/quality_gate.py --mode bootstrap
- 交付：python3 scripts/quality_gate.py --mode delivery --feature specs/<feature>

执行要求：
1. 新增模块或实现前，先做复用检查：检索项目内现有实现，记录结论（直接复用 / 配置 / 适配 / 无满足条件），再决定是否新建。可用 `/speckit.csdd.navigate` 获取现有结构。
2. 修改已有功能前，先定位实际接入入口的权威实现，记录依据与证据等级（静态确认 / 运行时确认 / 推断 / 未知）；证据不足写“未知”，不得猜测。
3. 以下情况记录具体缺口并交给负责人判断：验收预期不明确、越过模块或公共接口边界、需要破坏数据或兼容性、需要删测试或跳过门禁。
4. 禁止提交密钥与真实客户数据；测试未运行或业务检查未配置时，不得声称完成交付。
<!-- CSDD:END -->
EOF
      ;;
    CONTRIBUTING.md) cat <<'EOF'

<!-- CSDD:BEGIN 由 csdd-install.sh 追加，请勿手改本区块 -->
## 质量门禁

提交前运行 `python3 scripts/quality_gate.py --mode bootstrap` 与单元测试。
业务检查命令配置在 `quality-policy.json` 的 `checks`；未配置时 delivery 会阻断。
<!-- CSDD:END -->
EOF
      ;;
  esac
}

say "包:   $PKG"
say "目标: $TARGET"
say "模式: $([ "$APPLY" -eq 1 ] && echo 执行 || echo 预演)"
say ""

if [ ! -f "$TARGET/.specify/integration.json" ] && [ ! -f "$TARGET/.specify/init-options.json" ]; then
  say "目标仓库的 spec-kit 未初始化（缺 .specify/integration.json）。先执行："
  say ""
  say "  cd \"$TARGET\""
  if [ "$AGENT" = "codex" ]; then
    say "  uvx --from specify-cli==1.1.3 specify init --here \\"
    say "    --integration codex --integration-options=\"--skills\" \\"
    say "    --script sh --ignore-agent-tools --non-interactive"
  else
    # claude 集成默认就是技能格式，实测不接受 --skills；其它 agent 的参数本包未验证
    say "  uvx --from specify-cli==1.1.3 specify init --here \\"
    say "    --integration $AGENT --script sh --ignore-agent-tools --non-interactive"
  fi
  say ""
  say "目录非空时 specify init 的非交互模式必须加 --force 才会合并（实测）。推荐直接用 csdd-bootstrap.sh。初始化完成后再运行本脚本。"
  exit 2
fi

CONFLICTS=0
PLANNED=0

say "== 文件 =="
while IFS= read -r src; do
  rel="${src#"$PAYLOAD"/}"
  dst="$TARGET/$rel"
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      plan "相同" "$rel"
    elif is_append "$rel"; then
      if grep -q 'CSDD:BEGIN' "$dst"; then
        plan "已含" "${rel}（已有 CSDD 区块）"
      else
        plan "追加" "${rel}（保留原内容，追加 CSDD 区块）"; PLANNED=$((PLANNED+1))
      fi
    elif [ "$rel" = ".specify/memory/constitution.md" ] && grep -q '\[PROJECT_NAME\]' "$dst"; then
      plan "替换占位" "${rel}（spec-kit 默认模板未填写）"; PLANNED=$((PLANNED+1))
    elif [ "$FORCE" -eq 1 ]; then
      plan "覆盖" "$rel"; PLANNED=$((PLANNED+1))
    else
      plan "冲突" "${rel}（已存在且不同；--force 才覆盖）"; CONFLICTS=$((CONFLICTS+1))
    fi
  else
    plan "新增" "$rel"; PLANNED=$((PLANNED+1))
  fi
done < <(find "$PAYLOAD" -type f | sort)

say ""
say "== 说明型文件（不随 payload 整份复制，只写中性区块）=="
for rel in $APPEND_FILES; do
  dst="$TARGET/$rel"
  if [ ! -f "$dst" ]; then
    plan "新增" "${rel}（中性 CSDD 区块）"; PLANNED=$((PLANNED+1))
  elif grep -q 'CSDD:BEGIN' "$dst"; then
    plan "已含" "${rel}（已有 CSDD 区块）"
  else
    plan "追加" "${rel}（保留原内容，追加 CSDD 区块）"; PLANNED=$((PLANNED+1))
  fi
done

say ""
say "== 必须已存在（不覆盖）=="
if [ -f "$TARGET/README.md" ]; then
  plan "ok" "README.md"
else
  plan "缺失" "README.md（quality-policy.json 的 required_files 要求它）"
  CONFLICTS=$((CONFLICTS+1))
fi

say ""
say "== .gitignore =="
GI="$TARGET/.gitignore"
for line in "__pycache__/" "*.pyc" "reports/" ".workbuddy/" ".workbuddy-ai/memory/"; do
  if [ -f "$GI" ] && grep -qxF "$line" "$GI"; then
    plan "已有" "$line"
  else
    plan "追加" "$line"; PLANNED=$((PLANNED+1))
  fi
done

say ""
say "== 过期功能指针 =="
FEAT="$TARGET/.specify/feature.json"
if [ -f "$FEAT" ]; then
  FD="$(sed -n 's/.*"feature_directory"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FEAT" || true)"
  if [ -n "${FD}" ] && [ ! -d "$TARGET/${FD}" ]; then
    plan "移除" ".specify/feature.json（指向不存在的 ${FD}）"; PLANNED=$((PLANNED+1))
  else
    plan "保留" ".specify/feature.json"
  fi
else
  plan "无" ".specify/feature.json"
fi

say ""
if [ "$APPLY" -eq 0 ]; then
  say "预演结束：计划写入 ${PLANNED} 项，冲突 ${CONFLICTS} 项。加 --apply 执行。"
  exit 0
fi

if [ "$CONFLICTS" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
  say "有 ${CONFLICTS} 项冲突，未写入任何文件。"
  say "逐个确认后加 --force，或先手工处理冲突项。"
  exit 3
fi

say "== 写入 =="
while IFS= read -r src; do
  rel="${src#"$PAYLOAD"/}"
  dst="$TARGET/$rel"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then continue; fi
  if [ -f "$dst" ] && is_append "$rel"; then
    if grep -q 'CSDD:BEGIN' "$dst"; then continue; fi
    append_block "$rel" >> "$dst"
    say "  追加 $rel"
    continue
  fi
  if [ -f "$dst" ] && [ "$FORCE" -eq 0 ]; then
    # 唯一例外：spec-kit 默认宪章是未填写的占位模板，替换不算破坏
    if [ "$rel" = ".specify/memory/constitution.md" ] && grep -q '\[PROJECT_NAME\]' "$dst"; then :; else continue; fi
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  say "  写入 $rel"
done < <(find "$PAYLOAD" -type f | sort)

for rel in $APPEND_FILES; do
  dst="$TARGET/$rel"
  if [ -f "$dst" ] && grep -q 'CSDD:BEGIN' "$dst"; then continue; fi
  if [ -f "$dst" ]; then
    append_block "$rel" >> "$dst"; say "  追加 $rel"
  else
    append_block "$rel" | sed '1{/^$/d;}' > "$dst"; say "  新增 $rel"
  fi
done

touch "$GI"
for line in "__pycache__/" "*.pyc" "reports/" ".workbuddy/" ".workbuddy-ai/memory/"; do
  grep -qxF "$line" "$GI" || printf '%s\n' "$line" >> "$GI"
done
say "  更新 .gitignore"

if [ -f "$FEAT" ]; then
  FD="$(sed -n 's/.*"feature_directory"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FEAT" || true)"
  if [ -n "${FD}" ] && [ ! -d "$TARGET/${FD}" ]; then
    rm -f "$FEAT"; say "  移除 .specify/feature.json"
  fi
fi

say ""
say "== 自检 =="
PY=""
for c in python3.11 python3; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
  say "  未找到 python3，跳过自检"
else
  GATE_RC=0; GATE_OUT="$(cd "$TARGET" && "$PY" scripts/quality_gate.py --mode bootstrap 2>&1)" || GATE_RC=$?
  printf '%s\n' "$GATE_OUT"
  if [ "$GATE_RC" -eq 0 ]; then
    say "  bootstrap 通过（${PY}）"
  elif printf '%s' "$GATE_OUT" | grep -q 'broken local link: \.claude/'; then
    # 治理文件已写入；失败来自 .claude/ 下第三方技能文档的示例链接，不是本次安装的问题
    say "  bootstrap 失败，原因是 .claude/ 下第三方扩展技能文档的示例链接被链接扫描误判（README「已知限制」）。"
    exit 5
  else
    say "  bootstrap 失败：先修报错，不要跳过"
    exit 4
  fi
  ( cd "$TARGET" && "$PY" -m unittest discover -s tests >/dev/null 2>&1 ) \
    && say "  单测通过" || say "  单测未通过，请人工查看"
fi

say ""
say "== 下一步（必须手工完成）=="
say "1. specify integration install ${AGENT} && specify integration use ${AGENT}"
say "2. 填 quality-policy.json 的 checks：build / test / format / architecture / security"
say "3. 建 specs/<feature>/acceptance.json 并更新 .specify/feature.json"
say "4. 做一次故意失败试验，确认 delivery 真的阻断"
say ""
say "本脚本不安装任何第三方扩展。需要时用 /speckit.csdd.extensions。"
