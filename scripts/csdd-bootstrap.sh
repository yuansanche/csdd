#!/usr/bin/env bash
# csdd-bootstrap.sh —— 一键部署：初始化 spec-kit → 装 CSDD 扩展 → 装治理层 → 可选装第三方扩展。
#
#   csdd-bootstrap.sh --target /repo --agent claude|codex [--yes] [--with-extensions all|id1,id2] [--force]
#
# 不带 --yes 只预演并停下（非交互环境安全）；带 --yes 才写入。
# 退出码：0 成功 / 1 用法或环境错误 / 2 初始化失败 / 3 治理层有冲突 / 4 自检或扩展安装失败
#         5 全部装成功，但装第三方扩展后门禁自检失败（Claude 集成的已知问题，见 README）
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET=""; AGENT=""; YES=0; FORCE=0; WITH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift ;;
    --agent) AGENT="${2:-}"; shift ;;
    --yes) YES=1 ;;
    --force) FORCE=1 ;;
    --with-extensions) WITH="${2:-}"; shift ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "需要存在的 --target 目录" >&2; exit 1; }
case "$AGENT" in claude|codex) ;; *) echo "--agent 只支持 claude 或 codex（其它集成未验证）" >&2; exit 1 ;; esac
TARGET="$(cd "$TARGET" && pwd)"

if command -v specify >/dev/null 2>&1 && specify --version 2>&1 | grep -q '1\.1\.3'; then SPEC=(specify)
elif command -v uvx >/dev/null 2>&1; then SPEC=(uvx --from "specify-cli==1.1.3" specify)
else echo "需要 specify 1.1.3 或 uvx" >&2; exit 1; fi
PY=""; for c in python3.11 python3; do if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi; done
[ -n "$PY" ] || { echo "需要 python3" >&2; exit 1; }

INITED=0
if [ -f "$TARGET/.specify/integration.json" ] || [ -f "$TARGET/.specify/init-options.json" ]; then INITED=1; fi
INIT_OPTS=(--here --non-interactive --integration "$AGENT" --script sh --ignore-agent-tools)
if [ "$AGENT" = "codex" ]; then INIT_OPTS+=(--integration-options=--skills); fi
# specify init 在非空目录的非交互模式下必须带 --force 才合并（实测：不带则退出 1）。
# 目标尚未初始化时，--force 只是合并进已有文件；实测 AGENTS.md 与 README.md 原内容保留。
if [ -n "$(ls -A "$TARGET" | grep -v -x '\.git' || true)" ]; then INIT_OPTS+=(--force); fi
FARGS=(); if [ "$FORCE" -eq 1 ]; then FARGS+=(--force); fi

IDS=""
if [ "$WITH" = "all" ]; then
  IDS="$("$PY" - "$PKG/extensions.manifest.json" <<'PY'
import json, sys
print(" ".join(c["id"] for c in json.load(open(sys.argv[1], encoding="utf-8"))["components"]))
PY
)"
else IDS="${WITH//,/ }"; fi

echo "包: $PKG"; echo "目标: $TARGET"; echo "agent: $AGENT"
if [ "$YES" -ne 1 ]; then
  echo; echo "[预演] 未加 --yes，不写任何文件。计划："
  if [ "$INITED" -eq 0 ]; then echo "  1. specify init ${INIT_OPTS[*]}"; else echo "  1. spec-kit 已初始化，跳过"; fi
  echo "  2. specify extension add <本包> --dev"
  echo "  3. csdd-install.sh --apply"
  if [ -n "$IDS" ]; then echo "  4. 安装第三方扩展: $IDS"; else echo "  4. 不装第三方扩展"; fi
  if [ "$INITED" -eq 1 ]; then echo; bash "$PKG/scripts/csdd-install.sh" --target "$TARGET" --agent "$AGENT"; fi
  echo; echo "确认后加 --yes 执行。"; exit 0
fi

if [ "$INITED" -eq 0 ]; then
  echo; echo "== 1 初始化 spec-kit"
  (cd "$TARGET" && "${SPEC[@]}" init "${INIT_OPTS[@]}" </dev/null) || { echo "初始化失败" >&2; exit 2; }
fi

echo; echo "== 2 安装 CSDD 扩展"
LISTED="$(cd "$TARGET" && "${SPEC[@]}" extension list 2>&1 || true)"
if grep -Eq '^[[:space:]]+csdd$' <<<"$LISTED"; then
  echo "  已安装，跳过"
else
  STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
  tar -C "$PKG" --exclude=.git -cf - . | tar -C "$STAGE" -xf -
  (cd "$TARGET" && echo y | "${SPEC[@]}" extension add "$STAGE" --dev) || { echo "安装 CSDD 扩展失败" >&2; exit 4; }
fi

echo; echo "== 3 安装治理层"
INST="$TARGET/.specify/extensions/csdd/scripts/csdd-install.sh"
bash "$INST" --target "$TARGET" --agent "$AGENT" ${FARGS[@]+"${FARGS[@]}"}
rc=0; bash "$INST" --target "$TARGET" --agent "$AGENT" --apply ${FARGS[@]+"${FARGS[@]}"} || rc=$?
KNOWN_GATE=0
case "$rc" in
  0) ;;
  3) echo "治理层有冲突，未写入。逐个确认后加 --force。" >&2; exit 3 ;;
  5) KNOWN_GATE=1 ;;
  *) echo "治理层安装失败（exit=$rc）" >&2; exit 4 ;;
esac

FAILED=""
if [ -n "$IDS" ]; then
  echo; echo "== 4 安装第三方扩展: $IDS"
  for id in $IDS; do
    if bash "$PKG/scripts/csdd-extensions.sh" --install "$id" --target "$TARGET"; then echo "  ok   $id"
    else echo "  失败 $id (exit=$?)"; FAILED="$FAILED $id"; fi
  done
fi

echo; echo "== 5 校验"
bash "$PKG/scripts/verify-package.sh" --target "$TARGET" || echo "  payload 校验有不一致，见上"
GATE=0; GOUT="$(cd "$TARGET" && "$PY" scripts/quality_gate.py --mode bootstrap 2>&1)" || GATE=$?
printf '%s\n' "$GOUT"
if [ -n "$FAILED" ]; then echo "未装成功:$FAILED" >&2; exit 4; fi
if [ "$GATE" -ne 0 ] || [ "$KNOWN_GATE" -eq 1 ]; then
  # 按失败原因判断，不按本次是否装了扩展：重复运行时同样的问题仍在
  if [ "$KNOWN_GATE" -eq 1 ] || printf '%s' "$GOUT" | grep -q 'broken local link: \.claude/'; then
    echo "安装本身成功，但门禁自检失败：.claude/ 下第三方扩展技能文档里的示例链接被链接扫描误判（README「已知限制」）。需要在你们的门禁里排除 .claude/，并走评审。" >&2
    exit 5
  fi
  exit 4
fi
echo; echo "完成。安装不等于能力验证。"
