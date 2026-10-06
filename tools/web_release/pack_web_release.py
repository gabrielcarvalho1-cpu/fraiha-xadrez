#!/usr/bin/env python3
"""FRAIHA · monta a pasta de entrega da build Web (FRAIHA_WEB_<TAG>) a partir de um export Godot.

Inclui SEMPRE: os 9 arquivos index.* do export + engines/ (Stockfish) + voice/ (FRAIHA Voice).
Arquivos grandes vão em partes de 19 MiB (limite de cópia para o PC). ARQUIVOS-SHA256.txt lista
TODOS os arquivos finais (caminho relativo, tamanho, SHA256). O MONTAR-UPLOAD confere cada um, então
uma pasta voice/ (ou engines/) faltando ou corrompida PARA a montagem em vez de virar 404 no site.

Imagens (.png) vão como <arquivo>.png.b64 (texto base64): a cópia para o PC recomprime PNGs pequenos
(mesmos pixels, bytes diferentes) e isso quebraria a conferência de SHA256. O MONTAR-UPLOAD decodifica.

Uso: pack_web_release.py <export_dir> <web_dir_do_repo> <saida> <TAG> <commit>
"""
import base64, hashlib, os, shutil, sys

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


def files_needed(export_dir, web_dir):
    out = []
    for n in INDEX:
        out.append((n, os.path.join(export_dir, n)))
    for d, names in REQUIRED_DIRS.items():
        for n in names:
            out.append((d + "/" + n, os.path.join(web_dir, d, n)))
    missing = [rel for rel, src in out if not os.path.isfile(src) or os.path.getsize(src) == 0]
    if missing:
        raise SystemExit("ERRO: arquivos obrigatórios ausentes (nada foi gerado): " + ", ".join(missing))
    return out


def main(argv):
    if len(argv) != 6:
        raise SystemExit(__doc__)
    export_dir, web_dir, out, tag, commit = argv[1:]
    files = files_needed(export_dir, web_dir)
    if os.path.exists(out) and os.listdir(out):
        raise SystemExit("ERRO: pasta de saída já existe e não está vazia: " + out)
    os.makedirs(out, exist_ok=True)
    lines = ["# FRAIHA build Web %s · commit %s" % (tag, commit),
             "# caminho  tamanho  SHA256 — TODOS obrigatórios no bucket (o MONTAR-UPLOAD confere cada um)"]
    for rel, src in files:
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
    for name in ("MONTAR-UPLOAD.ps1", "CONFERIR-SITE.ps1"):
        src = os.path.join(here, name)
        with open(src, encoding="utf-8") as f:
            text = f.read().replace("__TAG__", tag)
        with open(os.path.join(out, name.replace(".ps1", "-%s.ps1" % tag)), "w", encoding="utf-8-sig", newline="\r\n") as f:
            f.write(text)
        cmd = name.replace(".ps1", "-%s" % tag)
        with open(os.path.join(out, cmd + ".cmd"), "w", newline="\r\n") as f:
            f.write('@echo off\ntitle FRAIHA %s\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%%~dp0%s.ps1"\npause\n' % (cmd, cmd))
    print("OK: %d arquivos (index %d + engines %d + voice %d) em %s" % (
        len(files), len(INDEX), len(REQUIRED_DIRS["engines"]), len(REQUIRED_DIRS["voice"]), out))


if __name__ == "__main__":
    main(sys.argv)
