#!/usr/bin/env python3
"""R55 · Painel de PERFIL da Home (canto superior direito, PC) a partir do recorte enviado pelo dono
(tools/ui_ref/home/perfil_home_ref.png, 1774x887, fundo transparente). Ficam a moldura, os ornamentos,
a coroinha, a moldura do retrato, o trilho da barra e o filete do meio; o que muda por jogador sai da
arte e o jogo desenha ao vivo por cima (ui_v022/main_hub.gd): retrato, nome, liga/PL, preenchimento da
barra, insígnia da liga e o STATUS do jogador. Saída: ui_v022/art/home_profile_frame.png (metade do
tamanho; o jogo reduz para a tela) e ui_v022/art/home_profile_under.png: o pedaço da Home (v8) onde
ficava o painel antigo, SEM ele (preenchido pela floresta/céu em volta) — vai por baixo da moldura nova,
que tem cantos vazados. A arte da Home (v8) não muda (o celular também a usa).
Uso: python3 tools/home_profile_art.py"""
import os
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "tools/ui_ref/home/perfil_home_ref.png")
OUT = os.path.join(ROOT, "ui_v022/art/home_profile_frame.png")
# caixas em px da referência: (x0, y0, x1, y1, colunas de amostra à esquerda/direita)
TEXT_BOXES = [   # (caixa, colunas LIMPAS de onde vem a cor de cada linha)
    ((1368, 238, 1600, 522), [(1596, 1608)]),              # insígnia (escudo da liga)
    ((792, 196, 1400, 306), [(778, 790), (1408, 1420)]),   # nome
    ((602, 322, 1176, 412), [(1190, 1350)]),               # liga · PL
    ((360, 586, 1420, 744), [(250, 350), (1440, 1560)]),   # frase -> status do jogador
]
PORTRAIT = (214, 220, 536, 498)
BAR = (630, 440, 1302, 485)


def row_fill(a, box, cols, feather=10.0):
    x0, y0, x1, y1 = box
    row = np.median(np.concatenate([a[y0:y1, c0:c1] for c0, c1 in cols], axis=1), axis=1)
    fill = np.repeat(row[:, None, :], x1 - x0, axis=1)
    w = np.zeros((y1 - y0, x1 - x0), np.float32)
    w[3:-3, 3:-3] = 1.0
    w = cv2.GaussianBlur(w, (0, 0), feather)
    w[int(feather):-int(feather), int(feather):-int(feather)] = 1.0
    reg = a[y0:y1, x0:x1]
    a[y0:y1, x0:x1] = reg * (1 - w[..., None]) + fill * w[..., None]


a = np.array(Image.open(SRC).convert("RGBA")).astype(np.float32)
rgb = a[..., :3]
for b, cols in TEXT_BOXES: row_fill(rgb, b, cols)
# miolo do retrato: fundo escuro liso (o avatar cobre por cima)
x0, y0, x1, y1 = PORTRAIT
corner = np.concatenate([rgb[y0 + 4:y0 + 14, x0 + 4:x0 + 14].reshape(-1, 3), rgb[y1 - 14:y1 - 4, x1 - 14:x1 - 4].reshape(-1, 3)])
rgb[y0:y1, x0:x1] = np.median(corner, axis=0)
rgb[y1 - 4:y1 + 12, x0 + 30:x1 - 30] = np.median(corner, axis=0)   # pé da peça antiga embaixo
# trilho da barra sem o preenchimento dourado: cada linha recebe a mediana do trilho vazio
x0, y0, x1, y1 = BAR
row = np.median(rgb[y0:y1, 760:1280], axis=1)
rgb[y0:y1, x0:x1] = row[:, None, :]
img = np.dstack([np.clip(rgb, 0, 255), a[..., 3]]).astype(np.uint8)
im = Image.fromarray(img, "RGBA").resize((887, 444), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
im.save(OUT, optimize=True)
print(OUT, im.size)

# ---------- remendo por baixo: o painel antigo some da Home (só no PC, só nesta área) ----------
HOME = os.path.join(ROOT, "ui_v022/assets/home_forest_v8.png")
UNDER = os.path.join(ROOT, "ui_v022/art/home_profile_under.png")
OLD = (1220, 22, 1648, 240)          # painel antigo na arte da Home (px de 1672x941), com folga
PATCH = (1196, 6, 1672, 258)         # área do remendo
h = np.array(Image.open(HOME).convert("RGB"))
mask = np.zeros(h.shape[:2], np.uint8)
mask[OLD[1]:OLD[3], OLD[0]:OLD[2]] = 255
bgr = cv2.inpaint(cv2.cvtColor(h, cv2.COLOR_RGB2BGR), mask, 12, cv2.INPAINT_TELEA)
rgb2 = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
x0, y0, x1, y1 = PATCH
crop = rgb2[y0:y1, x0:x1]
# borda do remendo esfumada para o fundo (alfa 0 nas bordas que não encostam no limite da tela)
al = np.zeros(crop.shape[:2], np.float32)
al[10:-10, 10:] = 1.0
al = cv2.GaussianBlur(al, (0, 0), 4.0)
al[OLD[1] - y0:OLD[3] - y0, OLD[0] - x0:OLD[2] - x0] = 1.0
Image.fromarray(np.dstack([crop, (al * 255).astype(np.uint8)]), "RGBA").save(UNDER, optimize=True)
print(UNDER, crop.shape)
