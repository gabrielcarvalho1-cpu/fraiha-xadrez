#!/usr/bin/env python3
"""R55 · Painel CONFIGURAÇÕES da partida no PC (Ranked, Casual e contra o bot), a partir da arte enviada
pelo dono (tools/ui_ref/config/configuracoes_ref.png, 266x243). Fica só a MOLDURA (madeira, cantos dourados,
rebites e o filete dourado do cabeçalho); o miolo vira o fundo liso de cada faixa. Engrenagem, título,
ícones, textos, separadores e chaves liga/desliga são desenhados AO VIVO pelo jogo (ranked/board_skin.gd),
nítidos em qualquer janela. Saída: ranked/art/desk_settings_frame.png. Uso: python3 tools/desk_settings_art.py"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "tools/ui_ref/config/configuracoes_ref.png")
OUT = os.path.join(ROOT, "ranked/art/desk_settings_frame.png")
X0, X1 = 10, 254          # miolo (dentro da madeira)
HEAD = (10, 47)           # faixa do cabeçalho (y)
BODY = (50, 233)          # corpo (y)


def flat(a, y0, y1):
    """Cada linha recebe a mediana das bordas internas (sem texto): degradê vertical liso."""
    side = np.concatenate([a[y0:y1, X0 + 2:X0 + 6], a[y0:y1, X1 - 6:X1 - 2]], axis=1)
    row = np.median(side, axis=1)
    return np.repeat(row[:, None, :], X1 - X0, axis=1)


a = np.array(Image.open(SRC).convert("RGBA")).astype(np.float32)
rgb = a[..., :3]
out = rgb.copy()
for y0, y1 in [HEAD, BODY]:
    out[y0:y1, X0:X1] = flat(rgb, y0, y1)
img = np.dstack([np.clip(out, 0, 255), a[..., 3]]).astype(np.uint8)
Image.fromarray(img, "RGBA").save(OUT, optimize=True)
print(OUT, img.shape)
