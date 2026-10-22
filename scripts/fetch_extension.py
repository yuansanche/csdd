#!/usr/bin/env python3
"""把已校验过整包哈希的扩展压缩包解压到 out_dir（只用标准库，不依赖 unzip）。

用法: fetch_extension.py <zip> <out_dir> [--include a,b,c] [--yml-sha HEX] [--tree-sha HEX]
成功时 stdout 只打印 out_dir；诊断信息写 stderr。退出码 1 = 校验失败或压缩包不安全。
"""
import argparse
import hashlib
import os
import stat
import sys
import zipfile
from pathlib import PurePosixPath

MAX_FILES = 3000
MAX_BYTES = 200 * 1024 * 1024


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def tree_hash(base):
    """对按路径排序的 (相对路径, 内容 sha256) 求哈希；与清单里 tree_sha256 的算法一致。"""
    h = hashlib.sha256()
    rels = sorted(
        os.path.relpath(os.path.join(r, f), base).replace(os.sep, "/")
        for r, _, fs in os.walk(base) for f in fs
    )
    for rel in rels:
        h.update(rel.encode())
        with open(os.path.join(base, rel), "rb") as fh:
            h.update(hashlib.sha256(fh.read()).digest())
    return h.hexdigest(), len(rels)


def safe_parts(name):
    p = PurePosixPath(name)
    if p.is_absolute() or ".." in p.parts or "\\" in name:
        die(f"压缩包含不安全路径，拒绝: {name}")
    return p.parts


def find_root(infos):
    """extension.yml 所在目录（最多一层子目录）；有多个时取路径最短者。"""
    ys = [i.filename for i in infos
          if not i.is_dir() and PurePosixPath(i.filename).name == "extension.yml"
          and len(PurePosixPath(i.filename).parts) <= 2]
    if not ys:
        die("压缩包里没有位于根或一层子目录的 extension.yml")
    ys.sort(key=lambda s: len(s))
    return ys[0][: -len("extension.yml")]


def wanted(rel, include):
    return not include or any(rel == p or rel.startswith(p + "/") for p in include)


def extract(zpath, out, include):
    z = zipfile.ZipFile(zpath)
    infos = z.infolist()
    files = [i for i in infos if not i.is_dir()]
    if len(files) > MAX_FILES or sum(i.file_size for i in files) > MAX_BYTES:
        die("压缩包条目数或解压后体积超出上限，拒绝")
    root = find_root(infos)
    n = 0
    for i in files:
        if not i.filename.startswith(root):
            continue
        rel = i.filename[len(root):]
        parts = safe_parts(rel)
        if not wanted(rel, include):
            continue
        dst = os.path.join(out, *parts)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as fh:
            fh.write(z.read(i))
        mode = (i.external_attr >> 16) & 0o777
        if mode & stat.S_IXUSR:
            os.chmod(dst, 0o755)
        n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zip")
    ap.add_argument("out")
    ap.add_argument("--include", default="")
    ap.add_argument("--yml-sha", default="")
    ap.add_argument("--tree-sha", default="")
    a = ap.parse_args()
    include = [x for x in a.include.split(",") if x]
    os.makedirs(a.out, exist_ok=True)
    n = extract(a.zip, a.out, include)
    yml = os.path.join(a.out, "extension.yml")
    if not os.path.isfile(yml):
        die("过滤后没有 extension.yml（include 清单漏了它）")
    with open(yml, "rb") as fh:
        ys = hashlib.sha256(fh.read()).hexdigest()
    if a.yml_sha and ys != a.yml_sha:
        die(f"extension.yml 哈希与审计记录不一致\n  期望 {a.yml_sha}\n  实际 {ys}")
    th, cnt = tree_hash(a.out)
    if a.tree_sha and th != a.tree_sha:
        die(f"目录树哈希不一致\n  期望 {a.tree_sha}\n  实际 {th}")
    print(f"解压 {n} 个文件；extension.yml={ys[:12]}… 树哈希={th[:12]}…({cnt} 文件)", file=sys.stderr)
    print(a.out)


if __name__ == "__main__":
    main()
