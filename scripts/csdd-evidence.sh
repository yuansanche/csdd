#!/usr/bin/env bash
# BrownKit 证据树的状态检查，以及把证据目录加进 blueprint 的覆盖排除。
#
#   csdd-evidence.sh --status [--target /repo]            退出码 0=证据已就绪 10=未就绪
#   csdd-evidence.sh --exclude-evidence [--target /repo]  幂等；保留已有的排除项
set -uo pipefail

TARGET="."; ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift ;;
    --status) ACTION="status" ;;
    --exclude-evidence) ACTION="exclude" ;;
    --auto-enrich) ACTION="auto" ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "需要 --status 或 --exclude-evidence" >&2; exit 1; }
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "目标目录不存在" >&2; exit 1; }
PY=""; for c in python3.11 python3; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -n "$PY" ] || { echo "需要 python3" >&2; exit 1; }

EVD="evidence"
for f in brownkit-config.yml .specify/extensions/brownkit/brownkit-config.yml; do
  [ -f "$TARGET/$f" ] || continue
  v="$(sed -n 's/^evidence_dir:[[:space:]]*"\{0,1\}\([^"#[:space:]]*\)"\{0,1\}.*/\1/p' "$TARGET/$f" | head -1)"
  if [ -n "$v" ]; then EVD="$v"; break; fi
done

if [ "$ACTION" = "status" ]; then
  have() { if [ -f "$TARGET/$EVD/$1" ]; then echo "有"; else echo "无"; fi; }
  echo "证据目录: $EVD"
  echo "  context.json:               $(have context.json)"
  echo "  discovery/candidates.md:    $(have discovery/candidates.md)   （scan 的产出）"
  echo "  discovery/domain-model.md:  $(have discovery/domain-model.md)"
  echo "  discovery/l1-capabilities.md: $(have discovery/l1-capabilities.md)"
  if [ -f "$TARGET/$EVD/context.json" ] && [ -f "$TARGET/$EVD/discovery/domain-model.md" ] && [ -f "$TARGET/$EVD/discovery/l1-capabilities.md" ]; then
    echo "证据就绪: 是（init、scan、discover 的产出都在，可直接读取）"; exit 0
  fi
  echo "证据就绪: 否（缺少上面标“无”的文件）"; exit 10
fi

if [ "$ACTION" = "auto" ]; then
  # 证据没就绪时不改：没有内容可读，自动执行只会输出“无匹配能力”
  bash "${BASH_SOURCE[0]}" --status --target "$TARGET" >/dev/null || { echo "证据未就绪，不改钩子"; exit 10; }
  HK="$TARGET/.specify/extensions.yml"
  [ -f "$HK" ] || { echo "没有 .specify/extensions.yml（还没有注册任何钩子）"; exit 0; }
  "$PY" - "$HK" <<'PYEOF'
import sys
p = sys.argv[1]; lines = open(p, encoding="utf-8").read().split("\n")
changed, section, in_enrich = 0, None, False
for i, l in enumerate(lines):
    if l and not l[0].isspace(): section = None
    if l.startswith("  ") and not l.startswith("   ") and l.strip().endswith(":") and not l.strip().startswith("-"):
        section = l.strip()[:-1]
    if l.strip().startswith("- extension:"): in_enrich = False
    if l.strip() == "command: speckit.brownkit.enrich": in_enrich = True
    if in_enrich and section in ("before_specify", "before_clarify") and l.strip() == "optional: true":
        lines[i] = l.replace("optional: true", "optional: false"); changed += 1
open(p, "w", encoding="utf-8").write("\n".join(lines))
print(f"enrich 钩子改为自动执行: {changed} 处（before_specify、before_clarify）" if changed else "enrich 钩子已是自动执行或未注册，不改")
PYEOF
  exit 0
fi

CFG="$TARGET/.specify/extensions/blueprint-index/blueprint-config.yml"
[ -f "$CFG" ] || { echo "未安装 blueprint-index（找不到 $CFG），跳过"; exit 0; }
"$PY" - "$CFG" "$EVD" <<'PYEOF'
import sys
p, ev = sys.argv[1], sys.argv[2]
DEFAULTS = ['".*"', "specs"]          # 写了列表就会替换默认值，所以要把默认的两项一起写上
item = lambda v: f"    - {v}"
lines = open(p, encoding="utf-8").read().split("\n")
ci = next((i for i, l in enumerate(lines) if l.rstrip() == "coverage:"), None)
if ci is None:
    out = "\n".join(lines).rstrip("\n") + "\n\ncoverage:\n  exclude:\n" + "\n".join(item(d) for d in DEFAULTS + [ev]) + "\n"
    open(p, "w", encoding="utf-8").write(out); print(f"新增 coverage.exclude: .*、specs、{ev}"); sys.exit(0)
end = len(lines)
for j in range(ci + 1, len(lines)):
    if lines[j] and not lines[j][0].isspace() and not lines[j].startswith("#"):
        end = j; break
block = lines[ci + 1:end]
ei = next((k for k, l in enumerate(block) if l.strip() == "exclude:"), None)
if ei is None:
    lines[ci + 1:ci + 1] = ["  exclude:"] + [item(d) for d in DEFAULTS + [ev]]
    open(p, "w", encoding="utf-8").write("\n".join(lines)); print(f"在 coverage 下新增 exclude: .*、specs、{ev}"); sys.exit(0)
last, items, k = ei, [], ei + 1
while k < len(block) and (block[k].strip().startswith("- ") or block[k].strip() == "" or block[k].strip().startswith("#")):
    if block[k].strip().startswith("- "):
        last = k; items.append(block[k].strip()[2:].split("#")[0].strip().strip('"'))
    k += 1
if ev in items:
    print(f"coverage.exclude 已含 {ev}，不改"); sys.exit(0)
add = [item(ev)] if items else [item(d) for d in DEFAULTS + [ev]]
lines[ci + 1 + last + 1:ci + 1 + last + 1] = add
open(p, "w", encoding="utf-8").write("\n".join(lines)); print(f"coverage.exclude 追加 {ev}")
PYEOF
