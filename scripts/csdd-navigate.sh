#!/usr/bin/env bash
# 新增模块前的导航：汇总已装的 Blueprint Index 与 BrownKit 的确定性脚本输出。
# 默认只读；没有架构地图时，加 --init-map 才会生成骨架（只写 .specify/memory/blueprint.md，且仅当它不存在）。
#
#   csdd-navigate.sh [--target /repo] [--init-map]
set -uo pipefail

TARGET="."; INIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift ;;
    --init-map) INIT=1 ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "目标目录不存在" >&2; exit 1; }
cd "$TARGET"
PY=""; for c in python3.11 python3; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done

# blueprint-index 的 check 需要 bash >= 5.2：在常见位置找一个够新的
B52=""
for c in bash /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash; do
  p="$(command -v "$c" 2>/dev/null)" || continue
  if "$p" -c '[ "${BASH_VERSINFO[0]}" -gt 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 5 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }' 2>/dev/null; then B52="$p"; break; fi
done

EXT=".specify/extensions"; BD="$EXT/blueprint-index/scripts/bash"; MAP=".specify/memory/blueprint.md"
echo "== 1 架构地图（Blueprint Index）"
if [ ! -f "$BD/blueprint-state.sh" ]; then
  echo "  未安装 blueprint-index（csdd-extensions.sh --install blueprint-index）"
elif [ -z "$B52" ]; then
  echo "  找不到 bash >= 5.2（当前 ${BASH_VERSION}），无法运行地图检查。macOS: brew install bash"
else
  if [ ! -f "$MAP" ]; then
    if [ "$INIT" -eq 1 ]; then
      mkdir -p .specify/memory
      if "$B52" "$BD/blueprint-slice.sh" scaffold > "$MAP" 2>/tmp/csdd-nav-scaffold.err; then
        "$B52" "$BD/blueprint-state.sh" restamp >/dev/null 2>&1 || true
        echo "  没有地图，已生成骨架 $MAP（只含按目录切分的结构，说明文字待 agent 补充）"
      else
        rm -f "$MAP"; echo "  生成骨架失败: $(head -c 200 /tmp/csdd-nav-scaffold.err)"
      fi
    else
      echo "  还没有地图。加 --init-map 生成骨架，或在 agent 里运行 /speckit.blueprint-index.init --from-code"
    fi
  fi
  if [ -f "$MAP" ]; then "$B52" "$BD/blueprint-state.sh" check --human 2>&1 || true; fi
fi

echo
echo "== 2 技术栈（BrownKit detect-stack，已排除 .git/.specify/agent 目录与任意深度的依赖目录）"
BK="$EXT/brownkit/scripts/bash"
if [ ! -f "$BK/detect-stack.sh" ]; then
  echo "  未安装 brownkit（csdd-extensions.sh --install brownkit）"
elif [ -z "$PY" ]; then
  echo "  需要 python3"
else
  STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
  "$PY" - "$TARGET" "$STAGE" <<'PYEOF'
import os, shutil, subprocess, sys
src, dst = sys.argv[1], sys.argv[2]
SKIP_TOP = {".git", ".specify", ".claude", ".agents", ".codebuddy", ".dsh", "reports"}
SKIP_ANY = {"node_modules", ".venv", "venv", "__pycache__", "dist", "build", "target", ".next", ".turbo", "coverage"}
def ok(rel):
    parts = rel.split("/")
    return parts[0] not in SKIP_TOP and not (set(parts[:-1]) & SKIP_ANY)
files = None
if os.path.isdir(os.path.join(src, ".git")):
    p = subprocess.run(["git", "-C", src, "ls-files", "-co", "--exclude-standard"], capture_output=True, text=True)
    if p.returncode == 0:
        files = [f for f in p.stdout.split("\n") if f]
if files is None:
    files = []
    for d, ds, fs in os.walk(src):
        rel_d = os.path.relpath(d, src).replace(os.sep, "/")
        ds[:] = [x for x in ds if x not in SKIP_ANY and not (rel_d == "." and x in SKIP_TOP)]
        files += [(("" if rel_d == "." else rel_d + "/") + f) for f in fs]
n = 0
for rel in files:
    s = os.path.join(src, rel)
    if not ok(rel) or os.path.islink(s) or not os.path.isfile(s) or os.path.getsize(s) > 1_000_000:
        continue
    t = os.path.join(dst, rel); os.makedirs(os.path.dirname(t), exist_ok=True); shutil.copy2(s, t); n += 1
print(f"  检测副本含 {n} 个文件", file=sys.stderr)
PYEOF
  STACK="$(bash "$BK/detect-stack.sh" --root "$STAGE" 2>&1 || true)"
  printf '%s' "$STACK" | "$PY" -c '
import sys, json
try: d = json.loads(sys.stdin.read())
except Exception: print("  detect-stack 输出无法解析"); sys.exit(0)
p = d.get("project", {}); c = d.get("candidates", {}).get("tools", {})
print("  架构提示:", p.get("architecture_hint"))
print("  语言文件数:", ", ".join(f"{k} {v}" for k, v in (p.get("language_file_counts") or {}).items()))
m = p.get("package_manifests") or []
print(f"  清单 {len(m)} 个:", "; ".join(x["path"] for x in m[:10]) + (" ..." if len(m) > 10 else ""))
print("  框架:", ", ".join(p.get("frameworks") or []) or "未识别", "| CI:", ", ".join(p.get("ci_platforms") or []) or "无")
for k in ("test_runner", "build", "lint"):
    v = c.get(k) or []
    if v: print(f"  {k}:", "; ".join(x["command"] for x in v[:3]))
'
fi
echo
echo "== 3 交给 agent 继续（脚本不替你判断）"
echo "  按用户要做的事，读代码找职责相近的现有实现，给出复用结论并写明依据；改已有功能先找被入口调用的实现。"
