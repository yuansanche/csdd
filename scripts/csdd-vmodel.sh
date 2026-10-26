#!/usr/bin/env bash
# V-Model 追溯前置检查：当前功能目录里需求件、验收件是否齐全。
#
#   csdd-vmodel.sh --status [--target /repo]    退出码 0=齐全 10=缺
#
# v-model 的 setup-v-model.sh 按 git 分支名找功能目录（不读 .specify/feature.json），
# 在 master/main 分支上会去 specs/master 找，找不到还会建一个空目录。
# 所以运行 v-model 的脚本时要带上本脚本打印的 SPECIFY_FEATURE。
set -uo pipefail

TARGET="."
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift ;;
    --status) ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "目标目录不存在" >&2; exit 1; }

FJ="$TARGET/.specify/feature.json"
[ -f "$FJ" ] || { echo "没有 .specify/feature.json（还没跑过 specify）"; echo "READY=no"; exit 10; }
FD="$(sed -n 's/.*"feature_directory"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FJ" | head -1)"
[ -n "$FD" ] && [ -d "$TARGET/$FD" ] || { echo "feature.json 指向的目录不存在: ${FD:-空}"; echo "READY=no"; exit 10; }

NAME="$(basename "$FD")"
VM="$TARGET/$FD/v-model"
has() { if [ -f "$VM/$1" ]; then echo yes; else echo no; fi; }
REQ="$(has requirements.md)"; ACC="$(has acceptance-plan.md)"
echo "FEATURE_DIR=$FD"
echo "SPECIFY_FEATURE=$NAME"
echo "REQUIREMENTS=$REQ"
echo "ACCEPTANCE=$ACC"
if [ "$REQ" = yes ] && [ "$ACC" = yes ]; then echo "READY=yes"; exit 0; fi
echo "READY=no"; exit 10
