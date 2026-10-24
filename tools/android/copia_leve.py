#!/usr/bin/env python3
"""R183 · cópia "leve" do projeto SÓ para o export do app Android.
Copia o projeto para DESTINO e troca a compressão das imagens de "sem perda" (compress/mode=0) para WebP com perda
(compress/mode=1, qualidade 0,88). O projeto original (site e PC) não muda. Depois: importar e exportar no DESTINO.
Uso: copia_leve.py ORIGEM DESTINO"""
import os, re, shutil, subprocess, sys

src, dst = sys.argv[1], sys.argv[2]
if os.path.exists(dst):
    shutil.rmtree(dst)
shutil.copytree(src, dst, symlinks=True, ignore=lambda d, names: [x for x in names if x in (".git", "node_modules")
                or (os.path.basename(d) == "android" and x == "build")])
n = 0
for dp, dn, fn in os.walk(dst):
    rel = os.path.relpath(dp, dst)
    if rel.startswith((".godot", "android", "tests", "docs", "tools", "web")):
        continue
    for f in fn:
        if not f.endswith(".import"):
            continue
        p = os.path.join(dp, f)
        t = open(p, encoding="utf-8", errors="ignore").read()
        if 'importer="texture"' not in t or "\ncompress/mode=0" not in t:
            continue
        t = t.replace("\ncompress/mode=0", "\ncompress/mode=1")
        t = re.sub(r"\ncompress/lossy_quality=[0-9.]+", "\ncompress/lossy_quality=0.88", t)
        open(p, "w", encoding="utf-8").write(t)
        n += 1
print("imagens trocadas para WebP com perda:", n)
