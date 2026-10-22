#!/usr/bin/env python3
"""把清单里的第三方扩展压缩包缓存到 cache/（维护用，需要联网）。

  cache_extensions.py [--only id,id]

- 下载 source 并校验整包 sha256；不符则报错，不写缓存。
- 无 include 的组件：缓存原包。
- 有 include 的组件（如 v-model）：缓存按 include 过滤后的 zip（条目排序、时间戳固定），
  并核对它还原出的目录树哈希与清单里的 tree_sha256 一致。
- 把 mirror_file / mirror_sha256 写回 extensions.manifest.json。
"""
import argparse
import hashlib
import io
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fetch_extension as fe  # noqa: E402

PKG = HERE.parent
MANIFEST = PKG / "extensions.manifest.json"
CACHE = PKG / "cache"


def download(url):
    p = subprocess.run(["curl", "-fsSL", "--http1.1", "--retry", "3", "--retry-all-errors", "-m", "180", url],
                       capture_output=True)
    if p.returncode != 0:
        sys.exit(f"下载失败: {url}")
    return p.stdout


def filtered_zip(data, include):
    zin = zipfile.ZipFile(io.BytesIO(data))
    root = fe.find_root(zin.infolist())
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
        for i in sorted((x for x in zin.infolist() if not x.is_dir()), key=lambda x: x.filename):
            if not i.filename.startswith(root) or not fe.wanted(i.filename[len(root):], include):
                continue
            zi = zipfile.ZipInfo(i.filename, (1980, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = i.external_attr
            out.writestr(zi, zin.read(i))
    return buf.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    only = [x for x in ap.parse_args().only.split(",") if x]
    d = json.loads(MANIFEST.read_text(encoding="utf-8"))
    CACHE.mkdir(exist_ok=True)
    for c in d["components"]:
        if only and c["id"] not in only:
            continue
        data = download(c["source"])
        got = hashlib.sha256(data).hexdigest()
        if got != c["sha256"]:
            sys.exit(f"{c['id']}: 整包哈希与清单不符\n  期望 {c['sha256']}\n  实际 {got}")
        include = c.get("include") or []
        blob = filtered_zip(data, include) if include else data
        name = f"cache/{c['id']}-{c['version']}.zip"
        (PKG / name).write_bytes(blob)
        if include:
            with tempfile.TemporaryDirectory() as t:
                fe.extract(str(PKG / name), t, include)
                th, _ = fe.tree_hash(t)
            if th != c.get("tree_sha256"):
                sys.exit(f"{c['id']}: 过滤缓存包的目录树哈希与清单不符")
        c["mirror_file"] = name
        c["mirror_sha256"] = hashlib.sha256(blob).hexdigest()
        print(f"{c['id']:20s} {len(blob) // 1024:6d} KB  {c['mirror_sha256'][:16]}")
    MANIFEST.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
