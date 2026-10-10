#!/usr/bin/env python3
"""FRAIHA · R55.5 · nomes com impressão digital (SHA-256) para a build Web do Godot.

Por quê: o site servia index.pck / index.wasm / index.js com nomes FIXOS e Cache-Control: no-cache.
Todo reload baixava de novo ~182 MB (PCK) + ~38 MB (WASM). Com o nome derivado do CONTEÚDO:
  - o arquivo pode ter cache longo (immutable): se o nome é o mesmo, o conteúdo é o mesmo;
  - release novo gera nome novo: o index.html novo só aponta para arquivos novos (sem mistura);
  - o motor (WASM/JS, ~38 MB) só muda quando muda o Godot: entre releases do jogo ele continua em cache.

Nomes (h = 16 primeiros hex do SHA-256):
  motor  index-e<h>.js / .wasm / .audio.worklet.js / .audio.position.worklet.js  (h = SHA de todos juntos)
  pacote index-p<h>.pck                                                           (h = SHA do .pck)
  splash index-s<h>.png                                                           (h = SHA do .png)
O index.html continua index.html (cache curto + ETag: é ele que descobre release novo).

Fail-closed: se o index.html não tiver EXATAMENTE os pontos esperados do template Godot, nada é gerado.
"""
import hashlib, json, os, re

ENGINE_SUFFIXES = [".js", ".wasm", ".audio.worklet.js", ".audio.position.worklet.js"]
HASH_LEN = 16
CONFIG_RE = re.compile(r"const GODOT_CONFIG = (\{.*?\});\n")
SCRIPT_TAG = '<script src="index.js"></script>'
SPLASH_RE = re.compile(r'(?<![\w.\-/])index\.png(?![\w.])')
CACHE_TAG_ID = "fraiha-asset-cache"


def _sha_files(paths):
    """1 arquivo: SHA-256 puro (o nome bate com o ARQUIVOS-SHA256.txt). Vários: SHA-256 de todos em ordem."""
    h = hashlib.sha256()
    for i, p in enumerate(paths):
        if i:
            h.update(b"\0FRAIHA\0")
        with open(p, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""):
                h.update(b)
    return h.hexdigest()


def plan(export_dir):
    """Devolve (mapa {nome_publicado: caminho_origem}, html_novo, info) sem escrever nada."""
    html_path = os.path.join(export_dir, "index.html")
    with open(html_path, encoding="utf-8") as f:
        html = f.read()
    m = CONFIG_RE.search(html)
    if not m:
        raise SystemExit("ERRO fingerprint: GODOT_CONFIG não encontrado no index.html")
    cfg = json.loads(m.group(1))
    if cfg.get("executable") != "index" or cfg.get("mainPack") not in (None, "index.pck"):
        raise SystemExit("ERRO fingerprint: index.html já processado ou export inesperado (executable=%r)" % cfg.get("executable"))
    if html.count(SCRIPT_TAG) != 1:
        raise SystemExit("ERRO fingerprint: tag <script src=\"index.js\"> não encontrada exatamente 1 vez")
    if len(SPLASH_RE.findall(html)) < 1:
        raise SystemExit("ERRO fingerprint: referência ao splash index.png não encontrada")
    if 'id="%s"' % CACHE_TAG_ID in html:
        raise SystemExit("ERRO fingerprint: cache de assets já injetado")
    src = lambda n: os.path.join(export_dir, n)
    eng = _sha_files([src("index" + s) for s in ENGINE_SUFFIXES])[:HASH_LEN]
    pck = _sha_files([src("index.pck")])[:HASH_LEN]
    spl = _sha_files([src("index.png")])[:HASH_LEN]
    exe = "index-e" + eng
    pack = "index-p%s.pck" % pck
    splash = "index-s%s.png" % spl
    files = {exe + s: src("index" + s) for s in ENGINE_SUFFIXES}
    files[pack] = src("index.pck")
    files[splash] = src("index.png")
    cfg["executable"] = exe
    cfg["mainPack"] = pack
    cfg["fileSizes"] = {pack: os.path.getsize(src("index.pck")), exe + ".wasm": os.path.getsize(src("index.wasm"))}
    new_cfg = "const GODOT_CONFIG = %s;\n" % json.dumps(cfg, separators=(",", ":"), ensure_ascii=False)
    out = html[:m.start()] + new_cfg + html[m.end():]
    cache_js = _cache_script([pack], {pack: cfg["fileSizes"][pack]})
    out = out.replace(SCRIPT_TAG, cache_js + '\n\t\t<script src="%s.js"></script>' % exe, 1)
    out = SPLASH_RE.sub(splash, out)
    info = {"executable": exe, "mainPack": pack, "splash": splash}
    return files, out, info


def _cache_script(names, sizes):
    """Cache do PCK no Cache Storage do navegador (independe do cache HTTP).

    Navegadores não guardam arquivos enormes no cache HTTP (Firefox: entrada > 50 MB nunca vai para o
    disco; Chrome: entrada > 1/8 do tamanho do cache). O PCK tem ~182 MB, então só cabeçalho bom NÃO
    basta. Aqui o fetch do Godot para os nomes com impressão digital passa por caches.open():
      (o WASM, ~9 MB com Brotli na rede, cabe no cache HTTP normal com o cabeçalho immutable.)
      - acerto: devolve do disco local (0 bytes de rede);
      - falta: baixa normal (o Godot recebe o stream na hora) e grava uma cópia em paralelo;
      - só grava resposta 200 completa com o tamanho esperado; acerto com tamanho errado é apagado;
      - entradas de outros releases são apagadas depois que o jogo abriu (só 1 versão no disco);
      - qualquer erro (sem Cache Storage, modo privado, cota cheia) = fetch normal, nunca quebra o jogo.
    Desligar para diagnóstico: ?nocache=1 na URL."""
    cfg = json.dumps({"names": names, "sizes": sizes}, separators=(",", ":"))
    return ("<script id=\"%s\">/* FRAIHA R55.5 · cache local do PCK (nome = SHA-256; docs/web/R55_5_CACHE_WEB.md) */\n"
            "(function(){var C=%s,N='fraiha-assets-v1',W=window,F=W.fetch.bind(W);\n"
            "if(!W.caches||/[?&]nocache=1/.test(location.search))return;\n"
            "function want(u){var n=String(u).split('?')[0].split('/').pop();return C.names.indexOf(n)>=0?n:null}\n"
            "W.__fraihaCache={hits:[],misses:[],stored:[],errors:[]};var S=W.__fraihaCache;\n"
            "W.fetch=function(input,init){var n=typeof input==='string'?want(input):null;if(!n)return F(input,init);\n"
            "var url=new URL(n,location.href).href;\n"
            "return caches.open(N).then(function(c){return c.match(url).then(function(hit){\n"
            "if(hit&&+hit.headers.get('content-length')===C.sizes[n]){S.hits.push(n);return hit}\n"
            "if(hit)c.delete(url);S.misses.push(n);\n"
            "return F(url,init).then(function(r){var len=+r.headers.get('content-length');\n"
            "if(r.status===200&&!r.headers.get('content-encoding')&&len===C.sizes[n]){\n"
            "c.put(url,r.clone()).then(function(){S.stored.push(n)},function(e){S.errors.push(n+': '+e)})}\n"
            "return r})})}).catch(function(e){S.errors.push(n+': '+e);return F(input,init)})};\n"
            "W.addEventListener('load',function(){setTimeout(function(){caches.open(N).then(function(c){c.keys().then(function(ks){\n"
            "ks.forEach(function(k){if(!want(k.url))c.delete(k)})})}).catch(function(){})},60000)});\n"
            "})();</script>") % (CACHE_TAG_ID, cfg)


if __name__ == "__main__":
    import sys
    files, html, info = plan(sys.argv[1])
    print(json.dumps(info, indent=1))
    for k, v in sorted(files.items()):
        print(k, "<-", v)
