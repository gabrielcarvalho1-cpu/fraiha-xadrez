#!/usr/bin/env python3
"""R133 · painel AÇÕES (celular): a placa "AÇÕES" e o botão X tinham sido recortados como RETÂNGULOS da arte de
referência (vinham com folhagem e cantos escuros em volta → caixas pretas feias). Aqui ganham transparência: fica
só a placa (octógono + pedras laterais + enfeite de cima) e o botão (quadrado de cantos cortados), borda suave.
Lê a versão do git (sem transparência) e grava RGBA em ranked/art/. Uso: python3 tools/art/acoes_recorte_r133.py"""
import os, io, subprocess
from PIL import Image, ImageDraw
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SS = 4
SHAPES = {
    "mob_hud_plaque": [
        [(30, 9), (239, 9), (246, 16), (246, 66), (239, 73), (30, 73), (22, 65), (22, 17)],   # placa
        [(0, 43), (12, 30), (25, 43), (12, 56)], [(247, 43), (259, 31), (271, 43), (259, 55)],   # pedras
        [(116, 0), (150, 0), (143, 12), (133, 16), (123, 12)],   # enfeite de cima
    ],
    "mob_hud_close": [[(15, 7), (70, 7), (76, 13), (76, 71), (70, 77), (15, 77), (9, 71), (9, 13)]],
}
for name, polys in SHAPES.items():
    raw = subprocess.check_output(["git", "-C", ROOT, "show", f"8b22b06:ranked/art/{name}.png"])
    im = Image.open(io.BytesIO(raw)).convert("RGBA")
    m = Image.new("L", (im.width * SS, im.height * SS), 0)
    d = ImageDraw.Draw(m)
    for poly in polys: d.polygon([(x * SS, y * SS) for x, y in poly], fill=255)
    im.putalpha(m.resize(im.size, Image.LANCZOS))
    im.save(os.path.join(ROOT, f"ranked/art/{name}.png"), optimize=True)
    print(name, im.size)
