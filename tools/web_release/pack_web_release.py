#!/usr/bin/env python3
"""FRAIHA · monta a pasta de entrega da build Web (FRAIHA_WEB_<TAG>) a partir de um export Godot.

Inclui SEMPRE: os 9 arquivos index.* do export + engines/ (Stockfish) + voice/ (FRAIHA Voice).
Arquivos grandes vão em partes de 19 MiB (limite de cópia para o PC). ARQUIVOS-SHA256.txt lista
TODOS os arquivos finais (caminho relativo, tamanho, SHA256). O MONTAR-UPLOAD confere cada um, então
uma pasta voice/ (ou engines/) faltando ou corrompida PARA a montagem em vez de virar 404 no site.

Imagens (.png) vão como <arquivo>.png.b64 (texto base64): a cópia para o PC recomprime PNGs pequenos
(mesmos pixels, bytes diferentes) e isso quebraria a conferência de SHA256. O MONTAR-UPLOAD decodifica.

R55.5 (cache Web): por padrão os arquivos do motor, o PCK e o splash saem com o SHA-256 no nome
(tools/web_release/fingerprint_web.py) e o index.html aponta para eles. O index.html vai SOZINHO numa
segunda pasta de upload (UPLOAD-2-POR-ULTIMO): ele só entra no bucket depois que todos os arquivos que
ele cita já estão lá. --legado gera os nomes antigos (index.pck/index.wasm/index.js).

R55.6: o index.html (nos dois modos) recebe INLINE a recuperação de perda de contexto WebGL
(web/gl_recovery/fraiha-gl-recovery.js). Sem esse arquivo, nada é gerado.

AMBIENTE (QA × produção): --ambiente=staging|producao é OBRIGATÓRIO. O empacotador lê o index.pck
(tools/web_release/ambiente_web.py), confere feature de export + servidor efetivo com o ambiente declarado e
PARA se divergir (ex.: build de staging pedida como produção). O ambiente vai para o ARQUIVOS-SHA256.txt
("# AMBIENTE ...") e para o index.html (<meta name="fraiha-ambiente">); o MONTAR-UPLOAD mostra e confere.

Uso: pack_web_release.py <export_dir> <web_dir_do_repo> <saida> <TAG> <commit> --ambiente=staging|producao [--legado]
"""
import base64, hashlib, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fingerprint_web
import ambiente_web

PART = 19922944
INDEX = ["index.html", "index.js", "index.wasm", "index.pck", "index.png", "index.icon.png",
         "index.apple-touch-icon.png", "index.audio.worklet.js", "index.audio.position.worklet.js"]
# Pastas obrigatórias ao lado do index.html (o jogo carrega esses caminhos em runtime).
REQUIRED_DIRS = {
    "engines": ["stockfish-19-lite-single.js", "stockfish-19-lite-single.wasm", "COPYING-GPLv3.txt"],
    "voice": ["AgoraRTC_N-4.24.8.js", "fraiha-voice-bridge-v1.js", "LEIA-ME-VOZ.txt"],
}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest().upper()


# Arquivos opcionais do export que vão junto SE o index.html os citar (ex.: diagnóstico de reload).
OPTIONAL = ["reload_diag.js"]


GL_RECOVERY = os.path.join("gl_recovery", "fraiha-gl-recovery.js")
GL_TAG_ID = "fraiha-gl-recovery"


def inject_gl_recovery(html, web_dir):
    """Coloca o script de recuperação de contexto WebGL logo no começo do <head> (fail-closed)."""
    src = os.path.join(web_dir, GL_RECOVERY)
    if not os.path.isfile(src) or os.path.getsize(src) == 0:
        raise SystemExit("ERRO: %s ausente (recuperação de WebGL obrigatória)" % src)
    if 'id="%s"' % GL_TAG_ID in html:
        raise SystemExit("ERRO: index.html já tem a recuperação de WebGL")
    if html.count("<head>") != 1:
        raise SystemExit("ERRO: <head> não encontrado exatamente 1 vez no index.html")
    with open(src, encoding="utf-8") as f:
        js = f.read()
    if "</script" in js:
        raise SystemExit("ERRO: o script de recuperação não pode conter </script")
    return html.replace("<head>", '<head>\n<script id="%s">\n%s</script>' % (GL_TAG_ID, js), 1)


def files_needed(export_dir, web_dir, fp=None):
    out = []
    if fp is None:
        for n in INDEX:
            out.append((n, None if n == "index.html" else os.path.join(export_dir, n)))
    else:
        files, _html, _info = fp
        out.append(("index.html", None))                 # gerado (o conteúdo vem do fingerprint)
        for n in sorted(files):
            out.append((n, files[n]))
        for n in ["index.icon.png", "index.apple-touch-icon.png"]:
            out.append((n, os.path.join(export_dir, n)))
        for n in OPTIONAL:
            if os.path.isfile(os.path.join(export_dir, n)) and ('src="%s"' % n) in _html:
                out.append((n, os.path.join(export_dir, n)))
    for d, names in REQUIRED_DIRS.items():
        for n in names:
            out.append((d + "/" + n, os.path.join(web_dir, d, n)))
    missing = [rel for rel, src in out if src is not None and (not os.path.isfile(src) or os.path.getsize(src) == 0)]
    if missing:
        raise SystemExit("ERRO: arquivos obrigatórios ausentes (nada foi gerado): " + ", ".join(missing))
    return out


AMB_META = "fraiha-ambiente"


def inject_ambiente(html, amb):
    """Marca o ambiente no index.html (visível no código da página e conferido pelo MONTAR-UPLOAD)."""
    if 'name="%s"' % AMB_META in html:
        raise SystemExit("ERRO: index.html já tem a marca de ambiente")
    return html.replace("<head>", '<head>\n<meta name="%s" content="%s">' % (AMB_META, amb), 1)


def main(argv):
    amb_args = [a for a in argv[1:] if a.startswith("--ambiente")]
    args = [a for a in argv[1:] if a != "--legado" and not a.startswith("--ambiente")]
    legacy = "--legado" in argv[1:]
    if len(args) != 5:
        raise SystemExit(__doc__)
    if len(amb_args) != 1 or not amb_args[0].startswith("--ambiente="):
        raise SystemExit("ERRO: informe o ambiente: --ambiente=staging (QA) ou --ambiente=producao")
    ambiente = amb_args[0].split("=", 1)[1]
    export_dir, web_dir, out, tag, commit = args
    if not os.path.isfile(os.path.join(export_dir, "index.html")):
        raise SystemExit("ERRO: arquivos obrigatórios ausentes (nada foi gerado): index.html")
    if not os.path.isfile(os.path.join(export_dir, "index.pck")):
        raise SystemExit("ERRO: arquivos obrigatórios ausentes (nada foi gerado): index.pck")
    amb = ambiente_web.conferir(os.path.join(export_dir, "index.pck"), ambiente)   # fail-closed, antes de tudo
    fp = None if legacy else fingerprint_web.plan(export_dir)
    files = files_needed(export_dir, web_dir, fp)
    if fp is not None:
        html = fp[1]
    else:
        with open(os.path.join(export_dir, "index.html"), encoding="utf-8") as f:
            html = f.read()
    html = inject_gl_recovery(html, web_dir)          # valida ANTES de criar qualquer coisa
    html = inject_ambiente(html, ambiente)
    if os.path.exists(out) and os.listdir(out):
        raise SystemExit("ERRO: pasta de saída já existe e não está vazia: " + out)
    os.makedirs(out, exist_ok=True)
    lines = ["# FRAIHA build Web %s · commit %s" % (tag, commit),
             "# AMBIENTE %s - servidor %s" % (ambiente, amb["servidor"]),
             "# caminho  tamanho  SHA256 — TODOS obrigatórios no bucket (o MONTAR-UPLOAD confere cada um)"]
    if fp is not None:
        lines.insert(1, "# R55.5 nomes com SHA-256: motor %s · pacote %s · index.html sobe POR ULTIMO" % (fp[2]["executable"], fp[2]["mainPack"]))
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8", newline="") as w:
        w.write(html)
    for rel, src in files:
        if src is None:
            src = os.path.join(out, rel)
            lines.append("%s  %d  %s" % (rel, os.path.getsize(src), sha(src)))
            continue
        size = os.path.getsize(src)
        digest = sha(src)
        dest = os.path.join(out, *rel.split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if size > PART:
            with open(src, "rb") as f:
                i = 0
                while True:
                    chunk = f.read(PART)
                    if not chunk:
                        break
                    with open("%s.part%02d" % (dest, i), "wb") as w:
                        w.write(chunk)
                    i += 1
        elif rel.lower().endswith(".png"):
            with open(src, "rb") as f:
                text = base64.encodebytes(f.read()).decode("ascii")
            with open(dest + ".b64", "w", encoding="ascii", newline="\r\n") as w:
                w.write(text)
        else:
            shutil.copyfile(src, dest)
        lines.append("%s  %d  %s" % (rel, size, digest))
    with open(os.path.join(out, "ARQUIVOS-SHA256.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")
    here = os.path.dirname(os.path.abspath(__file__))
    for name in ("ROLLBACK-ANTES-DE-PUBLICAR.ps1", "MONTAR-UPLOAD.ps1", "CONFERIR-SITE.ps1"):
        src = os.path.join(here, name)
        with open(src, encoding="utf-8") as f:
            text = f.read().replace("__TAG__", tag)
        with open(os.path.join(out, name.replace(".ps1", "-%s.ps1" % tag)), "w", encoding="utf-8-sig", newline="\r\n") as f:
            f.write(text)
        cmd = name.replace(".ps1", "-%s" % tag)
        with open(os.path.join(out, cmd + ".cmd"), "w", newline="\r\n") as f:
            # fail-closed: o código de saída do PowerShell é devolvido DEPOIS do pause (sem isso o .cmd sai 0)
            f.write('@echo off\ntitle FRAIHA %s\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%%~dp0%s.ps1" %%*\nset "RC=%%ERRORLEVEL%%"\nif not "%%RC%%"=="0" echo FALHOU (codigo %%RC%%)\nif not defined FRAIHA_NO_PAUSE pause\nexit /b %%RC%%\n' % (cmd, cmd))
    print("OK: AMBIENTE %s (servidor %s) · %d arquivos (%s · engines %d + voice %d) em %s" % (
        ambiente_web.rotulo(ambiente), amb["servidor"],
        len(files), "legado" if legacy else "nomes com SHA-256 " + fp[2]["mainPack"],
        len(REQUIRED_DIRS["engines"]), len(REQUIRED_DIRS["voice"]), out))


if __name__ == "__main__":
    main(sys.argv)
