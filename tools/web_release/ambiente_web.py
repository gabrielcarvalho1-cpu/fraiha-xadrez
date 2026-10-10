#!/usr/bin/env python3
"""FRAIHA · AMBIENTE da build Web (QA/staging × produção), lido do PRÓPRIO index.pck exportado.

O cliente escolhe o servidor em online_v020/endpoint.gd pela feature de export:
  - preset "Web Alpha"    → feature "staging"    → online.cfg [staging] server_url (servidor de testes)
  - preset "Web Producao" → feature "production" → online.cfg [online]  server_url (servidor oficial)
Este módulo abre o PCK (sem executar nada), lê as features gravadas no project.binary e o online.cfg
empacotado, calcula o servidor que a build vai usar de fato e confere com o ambiente DECLARADO.
Qualquer divergência = SystemExit (fail-closed): uma build de staging nunca sai marcada como produção.

Uso: ambiente_web.py <index.pck> <staging|producao>   → imprime o ambiente e o servidor; exit 1 se divergir.
"""
import re, struct, sys

AMBIENTES = ("staging", "producao")
# Endpoints públicos (wss://, sem segredo). Produção confirmada no projeto: online.cfg [online],
# admin/src/config.js (production) e o teste online_smoke dos docs. Mudou o servidor oficial? Mude AQUI,
# de propósito, junto com o online.cfg — o gate recusa qualquer outro endereço para produção.
PRODUCAO_URL = "wss://fraiha-xadrez.onrender.com"
STAGING_URL = "wss://fraiha-xadrez-staging.onrender.com"
FEATURE = {"staging": "staging", "producao": "production"}


class Erro(SystemExit):
    pass


def _falha(msg):
    raise Erro("ERRO (ambiente): " + msg)


def ler_pck(path, nomes=("project.binary", "online.cfg")):
    """Devolve {nome: bytes} dos arquivos pedidos dentro do PCK (Godot 4, formato 2 ou 3)."""
    try:
        return _ler_pck(path, nomes)
    except (struct.error, UnicodeDecodeError, OSError) as e:
        _falha("PCK ilegível (%s): %s" % (path, e))


def _ler_pck(path, nomes):
    with open(path, "rb") as f:
        head = f.read(32)
        if len(head) < 32 or head[:4] != b"GDPC":
            _falha("%s não é um PCK do Godot" % path)
        ver, _ma, _mi, _pa, flags, fbase = struct.unpack_from("<IIIIIQ", head, 4)
        if ver not in (2, 3):
            _falha("formato de PCK desconhecido (%d)" % ver)
        if flags & 1:
            _falha("PCK criptografado: não dá para conferir o ambiente")
        if ver >= 3:
            diro, = struct.unpack("<Q", f.read(8))
        f.read(16 * 4)
        if ver >= 3:
            f.seek(diro)
        n, = struct.unpack("<I", f.read(4))
        achados = {}
        for _ in range(n):
            ln, = struct.unpack("<I", f.read(4))
            p = f.read(ln).rstrip(b"\0").decode("utf-8", "replace")
            off, size = struct.unpack("<QQ", f.read(16))
            f.read(16 + 4)                  # md5 + flags do arquivo
            nome = p[6:] if p.startswith("res://") else p
            if nome in nomes:
                achados[nome] = (off, size)
        out = {}
        for nome, (off, size) in achados.items():
            f.seek(fbase + off)
            out[nome] = f.read(size)
    return out


def features(project_binary):
    """Lê _custom_features (Variant STRING) do project.binary."""
    k = b"_custom_features"
    i = project_binary.find(k)
    if i < 0:
        return []
    j = i + len(k)
    _vlen, vtype, slen = struct.unpack_from("<III", project_binary, j)
    if vtype != 4:                          # Variant::STRING
        _falha("_custom_features com tipo inesperado (%d)" % vtype)
    s = project_binary[j + 12:j + 12 + slen].decode("utf-8")
    return [x.strip() for x in s.split(",") if x.strip()]


def cfg_url(text, secao):
    m = re.search(r"^\[%s\]\s*$(.*?)(?=^\[|\Z)" % re.escape(secao), text, re.M | re.S)
    if not m:
        return ""
    u = re.search(r'^server_url\s*=\s*"([^"]*)"', m.group(1), re.M)
    return u.group(1).strip() if u else ""


def resolver(pck):
    """Servidor que a build Web usa de fato (mesma regra do endpoint.gd para a Web)."""
    arqs = ler_pck(pck)
    if "project.binary" not in arqs:
        _falha("project.binary ausente no PCK")
    if "online.cfg" not in arqs:
        _falha("online.cfg ausente no PCK (a build ficaria sem servidor)")
    feats = features(arqs["project.binary"])
    text = arqs["online.cfg"].decode("utf-8-sig")
    online, staging = cfg_url(text, "online"), cfg_url(text, "staging")
    if "staging" in feats and "production" in feats:
        _falha("build marcada como staging E produção ao mesmo tempo")
    if "staging" in feats:
        amb, url = "staging", (staging or online)
    elif "production" in feats:
        amb, url = "producao", online
    else:
        amb, url = "", online
    return {"ambiente": amb, "features": feats, "servidor": url, "online": online, "staging": staging}


def conferir(pck, declarado):
    """Fail-closed: o ambiente declarado tem que bater com o PCK e com o servidor efetivo."""
    if declarado not in AMBIENTES:
        _falha("ambiente declarado inválido: %r (use staging ou producao)" % (declarado,))
    r = resolver(pck)
    if r["ambiente"] == "":
        _falha("a build não tem feature de ambiente (exporte pelo preset \"Web Alpha\" ou \"Web Producao\")")
    if r["ambiente"] != declarado:
        _falha("pediu %s, mas o PCK é de %s (features: %s, servidor %s)" % (
            declarado.upper(), r["ambiente"].upper(), ",".join(r["features"]), r["servidor"]))
    url = r["servidor"]
    if not url.startswith("wss://"):
        _falha("servidor efetivo não é wss:// (%r)" % url)
    if declarado == "producao":
        if "staging" in url.lower() or url == r["staging"] or url == STAGING_URL:
            _falha("build de PRODUÇÃO apontando para STAGING (%s)" % url)
        if url != PRODUCAO_URL:
            _falha("build de PRODUÇÃO com servidor %s; o oficial é %s" % (url, PRODUCAO_URL))
    else:
        if url == PRODUCAO_URL or "staging" not in url.lower():
            _falha("build de STAGING apontando para fora do staging (%s)" % url)
    return r


def rotulo(declarado):
    return "PRODUCAO" if declarado == "producao" else "STAGING (QA/testes)"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    r = conferir(sys.argv[1], sys.argv[2])
    print("AMBIENTE %s · servidor %s · features %s" % (rotulo(r["ambiente"]), r["servidor"], ",".join(r["features"])))
