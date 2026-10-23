#!/usr/bin/env bash
# 查看或切换 .specify/extensions.yml 里扩展钩子的"自动 / 询问"。
#
#   csdd-hooks.sh --list [--target /repo]
#   csdd-hooks.sh --set <钩子点> <命令> auto|ask [--target /repo]
#     例: --set after_specify speckit.v-model.requirements auto
#
# auto = optional: false（spec-kit 的技能会自动执行并等它结束）；ask = optional: true（只提示）。
set -uo pipefail

TARGET="."; ACTION=""; POINT=""; CMD=""; MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift ;;
    --list) ACTION="list" ;;
    --set) ACTION="set"; POINT="${2:-}"; CMD="${3:-}"; MODE="${4:-}"; shift 3 ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "需要 --list 或 --set" >&2; exit 1; }
if [ "$ACTION" = "set" ]; then case "$MODE" in auto|ask) ;; *) echo "第三个参数只能是 auto 或 ask" >&2; exit 1 ;; esac; fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "目标目录不存在" >&2; exit 1; }
HK="$TARGET/.specify/extensions.yml"
[ -f "$HK" ] || { echo "没有 .specify/extensions.yml（还没有注册任何钩子）"; exit 0; }
PY=""; for c in python3.11 python3; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -n "$PY" ] || { echo "需要 python3" >&2; exit 1; }

"$PY" - "$HK" "$ACTION" "$POINT" "$CMD" "$MODE" <<'PYEOF'
import sys
p, action, point, cmd, mode = sys.argv[1:6]
lines = open(p, encoding="utf-8").read().split("\n")
section, entry, rows = None, {}, []
def flush():
    if entry.get("command"): rows.append(dict(entry))
changed = 0
for i, l in enumerate(lines):
    s = l.strip()
    if l and not l[0].isspace(): section = None
    if l.startswith("  ") and not l.startswith("   ") and s.endswith(":") and not s.startswith("-"):
        flush(); entry.clear(); section = s[:-1]; continue
    if s.startswith("- extension:"):
        flush(); entry.clear(); entry.update(point=section, extension=s.split(":", 1)[1].strip())
    elif s.startswith("command:") and section: entry.update(point=section, command=s.split(":", 1)[1].strip())
    elif s.startswith("optional:") and section:
        entry["optional"] = s.split(":", 1)[1].strip(); entry["line"] = i
        if action == "set" and entry.get("point") == point and entry.get("command") == cmd:
            want = "false" if mode == "auto" else "true"
            if entry["optional"] != want:
                lines[i] = l.replace(entry["optional"], want); entry["optional"] = want; changed += 1
            entry["hit"] = True
flush()
if action == "list":
    print(f"{'钩子点':<20}{'命令':<34}模式")
    for r in rows:
        if r.get("point") and r.get("command"):
            print(f"{r['point']:<20}{r['command']:<34}{'自动' if r.get('optional') == 'false' else '询问'}")
    sys.exit(0)
if not any(r.get("hit") for r in rows) and not (entry.get("hit")):
    print(f"没找到钩子 {point} / {cmd}（扩展没装，或没注册这个钩子）"); sys.exit(2)
open(p, "w", encoding="utf-8").write("\n".join(lines))
print(f"{point} / {cmd} -> {'自动' if mode == 'auto' else '询问'}" + ("" if changed else "（本来就是）"))
PYEOF
