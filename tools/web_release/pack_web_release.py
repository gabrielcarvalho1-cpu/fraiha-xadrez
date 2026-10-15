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

R94 (memória em sessão longa): o index.js do export recebe SEMPRE a correção que reaproveita os IDs WebGL
(tools/web_release/gl_ids_reuse.py) ANTES dos nomes com SHA-256. Se o runtime mudar e a correção não
encaixar, o empacotamento PARA — nenhum export sai sem ela.

Uso: pack_web_release.py <export_dir> <web_dir_do_repo> <saida> <TAG> <commit> --ambiente=staging|producao [--legado]
"""
import base64, hashlib, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fingerprint_web
import ambiente_web
import gl_ids_reuse
import audio_samples_release
import conteudo_extra

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
CONTEUDO_META = "fraiha-conteudo"


def pck_paths(path):
    """Lista os caminhos guardados num .pck do Godot 4 (formato 3)."""
    import struct
    with open(path, "rb") as f:
        d = f.read()
    if d[:4] != b"GDPC":
        raise SystemExit("ERRO: %s não é um pacote Godot" % path)
    ver = struct.unpack_from("<I", d, 4)[0]
    if ver < 3:
        raise SystemExit("ERRO: formato de pacote inesperado (%d) em %s" % (ver, path))
    pos = struct.unpack_from("<Q", d, 32)[0]
    n = struct.unpack_from("<I", d, pos)[0]; pos += 4
    out = []
    for _ in range(n):
        l = struct.unpack_from("<I", d, pos)[0]; pos += 4
        out.append(d[pos:pos + l].rstrip(b"\0").decode("utf-8").replace("res://", "")); pos += l + 36
    return out


def conteudo_plan(export_dir):
    """R115 · pacote principal SEM o conteúdo extra + conteudo.pck COM ele (fail-closed nos dois sentidos)."""
    import fnmatch
    main = pck_paths(os.path.join(export_dir, "index.pck"))
    def is_extra(p):
        return any(fnmatch.fnmatchcase(p, pat) for pat in conteudo_extra.PATTERNS)
    vazou = [p for p in main if is_extra(p)]
    cp = os.path.join(export_dir, "conteudo.pck")
    if not os.path.isfile(cp):
        raise SystemExit("ERRO: conteudo.pck ausente — exporte também: --export-pack \"Web Conteudo\" <export>/conteudo.pck"
                         + (" (o pacote principal ainda tem o conteúdo extra: rode tools/web_release/conteudo_extra.py e exporte de novo)" if vazou else ""))
    if vazou:
        raise SystemExit("ERRO: o pacote principal ainda tem conteúdo extra (%s…): rode tools/web_release/conteudo_extra.py e exporte de novo" % vazou[0])
    extra = [p for p in pck_paths(cp) if p.endswith(".import") and is_extra(p)]
    esperados = len(conteudo_extra.files())
    if len(extra) != esperados:
        raise SystemExit("ERRO: conteudo.pck incompleto (%d de %d arquivos)" % (len(extra), esperados))
    name = "index-p%s.pck" % fingerprint_web._sha_files([cp])[:fingerprint_web.HASH_LEN]
    return name, cp, len(extra)


def inject_conteudo(html, name, size):
    if 'name="%s"' % CONTEUDO_META in html:
        raise SystemExit("ERRO: index.html já tem a marca do conteúdo extra")
    return html.replace("<head>", '<head>\n<meta name="%s" content="%s" data-size="%d">' % (CONTEUDO_META, name, size), 1)


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
    gl = gl_ids_reuse.garantir(export_dir)          # R94 · fail-closed; muda o index.js antes do SHA do nome
    au = audio_samples_release.garantir(export_dir)   # R99 · fail-closed; liberação segura das amostras de áudio
    # R106 · imagens com perda na qualidade aprovada (0,75): o export precisa ter sido feito depois do texture_quality.py
    import subprocess
    tq = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "texture_quality.py"), "--check"], capture_output=True, text=True)
    if tq.returncode != 0:
        raise SystemExit("ERRO: imagens fora da qualidade aprovada — rode tools/web_release/texture_quality.py e exporte de novo.\n" + tq.stdout[-800:])
    fp = None if legacy else fingerprint_web.plan(export_dir)
    cont = None
    if fp is not None:
        cont = conteudo_plan(export_dir)          # R115 · fail-closed
        fp[0][cont[0]] = cont[1]
    files = files_needed(export_dir, web_dir, fp)
    if fp is not None:
        html = fp[1]
    else:
        with open(os.path.join(export_dir, "index.html"), encoding="utf-8") as f:
            html = f.read()
    html = inject_gl_recovery(html, web_dir)          # valida ANTES de criar qualquer coisa
    html = inject_ambiente(html, ambiente)
    if cont is not None:
        html = inject_conteudo(html, cont[0], os.path.getsize(cont[1]))
    if os.path.exists(out) and os.listdir(out):
        raise SystemExit("ERRO: pasta de saída já existe e não está vazia: " + out)
    os.makedirs(out, exist_ok=True)
    lines = ["# FRAIHA build Web %s · commit %s" % (tag, commit),
             "# AMBIENTE %s - servidor %s" % (ambiente, amb["servidor"]),
             "# R94 correcao GL IDs: %s - index.js %s" % (gl["estado"], gl["sha_depois"]),
             "# R99 liberacao das amostras de audio: %s - index.js %s" % (au["estado"], au["sha_depois"]),
             "# R106 imagens WebP qualidade %s; musicas 96 kbps" % "0.75",
             "# R115 conteudo extra (baixa depois da Home): %s" % (("%s - %d arquivos" % (cont[0], cont[2])) if cont else "nao (legado)"),
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
