#!/usr/bin/env python3
"""FRAIHA · R115 · CARREGAMENTO MAIS RÁPIDO (Web): separa o CONTEÚDO EXTRA do pacote principal.

Conteúdo extra (baixado em segundo plano depois que a Home abre — web_content/conteudo_extra.gd):
  XEQUE e MARCHA (artes e sons; as FONTES ficam no principal, outras telas usam), cenários/peças das ligas
  Bronze → Challenger e as músicas das ligas Ferro/Bronze/Prata/Ouro.
O que fica no principal: Home, xadrez, Madeira, Ferro, Premium (Fundador/Club), contas, interface.

Este script (rodar ANTES do export, como o texture_quality.py):
  1) põe os padrões do conteúdo extra no exclude_filter dos presets "Web Alpha" e "Web Producao";
  2) cria/atualiza o preset "Web Conteudo" (só pacote: export_filter="resources" com a lista de arquivos).
Depois: --export-release "Web Alpha" …/index.html  e  --export-pack "Web Conteudo" …/conteudo.pck
--check: só confere (sai 1 se os presets não estiverem em dia).
"""
import fnmatch, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PRESETS = os.path.join(ROOT, "export_presets.cfg")
PATTERNS = [
    "xeque/art/*.png*", "xeque/audio/*",
    "marcha/art/*.png*", "marcha/audio/*",
    "cosmetics/v029/*",
    "cosmetics/v025/bronze_*", "cosmetics/v025/silver_*", "cosmetics/v025/gold_*",
    "music_v026/iron.mp3*", "music_v026/bronze.mp3*", "music_v026/silver.mp3*", "music_v026/gold.mp3*",
]
MAIN = ["Web Alpha", "Web Producao"]
PACK = "Web Conteudo"
SRC_EXT = (".png", ".mp3", ".wav", ".ogg")


def files():
    out = []
    for d, _dirs, names in os.walk(ROOT):
        rel_d = os.path.relpath(d, ROOT).replace(os.sep, "/")
        if rel_d.startswith((".godot", "tests", "tools", "docs", ".git")): continue
        for n in names:
            if not n.lower().endswith(SRC_EXT): continue
            rel = (n if rel_d == "." else rel_d + "/" + n)
            if not os.path.isfile(os.path.join(ROOT, rel + ".import")): continue
            if any(fnmatch.fnmatchcase(rel, p) for p in PATTERNS): out.append("res://" + rel)
    return sorted(out)


def blocks(text):
    return [m for m in re.finditer(r"^\[preset\.(\d+)\]\n(.*?)(?=^\[preset\.\d+\]\n|\Z)", text, re.S | re.M)]


def plan(text):
    bl = blocks(text)
    by_name = {}
    for m in bl:
        nm = re.search(r'^name="([^"]*)"', m.group(2), re.M).group(1)
        by_name[nm] = m
    new = text
    for nm in MAIN:
        m = by_name.get(nm)
        if m is None: raise SystemExit("ERRO: preset %r não encontrado" % nm)
        body = m.group(0)
        ex = re.search(r'^exclude_filter="([^"]*)"', body, re.M)
        cur = [x for x in ex.group(1).split(",") if x]
        add = [p for p in PATTERNS if p not in cur]
        if add:
            body2 = body.replace(ex.group(0), 'exclude_filter="%s"' % ",".join(cur + add), 1)
            new = new.replace(body, body2, 1)
    # preset do pacote extra: cópia do "Web Alpha" (mesmas opções) com a lista de arquivos
    lst = files()
    if not lst: raise SystemExit("ERRO: nenhum arquivo do conteúdo extra encontrado")
    src = blocks(new)
    alpha = [m for m in src if re.search(r'^name="Web Alpha"', m.group(2), re.M)][0]
    existing = [m for m in src if re.search(r'^name="%s"' % PACK, m.group(2), re.M)]
    idx = int(existing[0].group(1)) if existing else max(int(m.group(1)) for m in src) + 1
    body = alpha.group(0).replace("[preset.%s]" % alpha.group(1), "[preset.%d]" % idx, 1)
    body = body.replace("[preset.%s.options]" % alpha.group(1), "[preset.%d.options]" % idx, 1)
    body = re.sub(r'^name="Web Alpha"', 'name="%s"' % PACK, body, count=1, flags=re.M)
    body = re.sub(r'^runnable=true', 'runnable=false', body, count=1, flags=re.M)
    body = re.sub(r'^export_filter="[^"]*"', 'export_filter="resources"', body, count=1, flags=re.M)
    body = re.sub(r'^include_filter="[^"]*"', 'include_filter=""', body, count=1, flags=re.M)
    body = re.sub(r'^exclude_filter="[^"]*"', 'exclude_filter=""', body, count=1, flags=re.M)
    body = re.sub(r'^export_files=PackedStringArray\([^)]*\)\n', '', body, flags=re.M)
    body = re.sub(r'^(export_filter="resources"\n)', lambda m: m.group(1) + 'export_files=PackedStringArray(%s)\n' % ", ".join('"%s"' % f for f in lst), body, count=1, flags=re.M)
    if not body.endswith("\n"): body += "\n"
    if existing:
        new = new.replace(existing[0].group(0), body, 1)
    else:
        if not new.endswith("\n"): new += "\n"
        new += "\n" + body
    return new.rstrip("\n") + "\n", lst


def main(argv):
    text = open(PRESETS, encoding="utf-8").read()
    new, lst = plan(text)
    if "--check" in argv:
        if new != text:
            print("conteudo_extra: presets DESATUALIZADOS — rode tools/web_release/conteudo_extra.py"); return 1
        print("conteudo_extra: presets em dia (%d arquivos no conteúdo extra)" % len(lst)); return 0
    if new != text:
        open(PRESETS, "w", encoding="utf-8", newline="\n").write(new)
    print("conteudo_extra: %d arquivos no conteúdo extra; presets %s" % (len(lst), "atualizados" if new != text else "já em dia"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
