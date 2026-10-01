#!/usr/bin/env python3
"""Gera ui_v022/assets/home_forest_v2_details.png: camada TRANSPARENTE desenhada por cima da
arte oficial da Home (home_forest_v2.png fica intacta). Conteúdo:
  - olhos do gato fechados (dormindo) no lugar dos olhos amarelos estranhos;
  - duas pessoinhas atravessando a ponte (atrás do parapeito);
  - "YUME" gravado na pedra perto da placa (easter egg);
  - par de baquetas no chão, meio coberto pela grama (easter egg);
  - folhinha de cannabis escondida nas samambaias (easter egg).
Rodar na raiz do projeto: python3 tools/home_details_overlay.py
"""
from PIL import Image, ImageDraw
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "ui_v022/assets/home_forest_v2.png")
OUT = os.path.join(ROOT, "ui_v022/assets/home_forest_v2_details.png")

base = Image.open(SRC).convert("RGBA")
W, H = base.size
ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(ov)
px = ov.load()
bpx = base.load()


def put(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        px[x, y] = c


def blend_base(x, y, c, a):
    """Mistura c sobre a cor original (para 'gravar' sem parecer colado)."""
    r, g, b, _ = bpx[x, y]
    put(x, y, (int(r * (1 - a) + c[0] * a), int(g * (1 - a) + c[1] * a), int(b * (1 - a) + c[2] * a), 255))


# ------------------------------------------------------------------ 1. Gato dormindo
# Os olhos amarelos ficam em ~(218..229, 791..797) e (247..258, 791..797). Cobrimos com o
# pelo escuro do rosto e desenhamos duas pálpebras fechadas (arco suave), como gato dormindo.
FUR = (31, 34, 40, 255)
FUR_HI = (52, 56, 64, 255)
LID = (14, 15, 18, 255)
for (x0, x1) in [(216, 231), (245, 260)]:
    for y in range(789, 800):
        for x in range(x0, x1):
            r, g, b, _ = bpx[x, y]
            # só cobre o amarelo/claro do olho e um pouco em volta
            if (r > 120 and g > 90) or (y in (789, 799)):
                blend_base(x, y, FUR[:3], 0.9 if (r > 120 and g > 90) else 0.35)
# pálpebras: arco de 11 px, 2 px de espessura, caindo nas pontas (olho fechado sereno)
for (cx, cy) in [(223, 794), (252, 794)]:
    arc = [(-5, 2), (-4, 1), (-3, 0), (-2, 0), (-1, -1), (0, -1), (1, -1), (2, 0), (3, 0), (4, 1), (5, 2)]
    for dx, dy in arc:
        put(cx + dx, cy + dy, LID)
        put(cx + dx, cy + dy + 1, (LID[0], LID[1], LID[2], 160))
    # brilho sutil acima da pálpebra (volume da pálpebra)
    for dx in range(-3, 4):
        put(cx + dx, cy - 2, (FUR_HI[0], FUR_HI[1], FUR_HI[2], 110))

# ------------------------------------------------------------------ 2. Pessoas na ponte
# Parapeito da ponte: topo em ~y=512 (x≈1160) e ~y=508 (x≈1195). As figuras ficam ATRÁS
# do muro: só cabeça e ombros aparecem (escala real: pessoa ≈ 20 px, muro ≈ 12 px).
def person(x, top, cloak, hood, skin, hat=None, staff=False, pack=None):
    # cabeça 3x3
    for dx in range(3):
        for dy in range(3):
            put(x + dx, top + dy, skin)
    put(x + 1, top + 1, (skin[0] - 30, skin[1] - 30, skin[2] - 30, 255))  # sombra do rosto
    # capuz / chapéu
    if hat:
        for dx in range(-1, 4):
            put(x + dx, top - 1, hat)
        for dx in range(0, 3):
            put(x + dx, top - 2, hat)
    else:
        for dx in range(-1, 4):
            put(x + dx, top, hood)
        put(x - 1, top + 1, hood); put(x + 3, top + 1, hood)
        put(x, top - 1, hood); put(x + 1, top - 1, hood); put(x + 2, top - 1, hood)
    # ombros/tronco (5 px de largura) — até onde o parapeito esconde
    for dy in range(3, 9):
        for dx in range(-1, 4):
            c = cloak if dy > 3 else hood
            put(x + dx, top + dy, c)
    # luz lateral (tochas) no ombro esquerdo
    for dy in range(4, 8):
        put(x - 1, top + dy, (min(255, cloak[0] + 40), min(255, cloak[1] + 30), cloak[2], 255))
    if staff:
        for dy in range(-3, 9):
            put(x + 5, top + dy, (120, 86, 48, 255))
        put(x + 5, top - 4, (200, 170, 90, 255))
    if pack:
        for dy in range(3, 8):
            for dx in range(4, 6):
                put(x + dx, top + dy, pack)

# viajante com cajado (mais à esquerda) e aventureira de capa verde com mochila
person(1158, 504, cloak=(96, 58, 40, 255), hood=(132, 84, 52, 255), skin=(228, 184, 140, 255), staff=True)
person(1188, 500, cloak=(38, 92, 58, 255), hood=(56, 128, 76, 255), skin=(214, 168, 124, 255), hat=(70, 48, 28, 255), pack=(120, 78, 40, 255))
# apaga o que ficaria "na frente" do parapeito: tudo abaixo do topo do muro em cada coluna
# Topo do parapeito medido na arte: y=513 (x<1171), y=510 (1171..1206), y=513 (depois).
for x in range(1150, 1215):
    top = 510 if 1171 <= x <= 1206 else 513
    for y in range(top, 545):
        put(x, y, (0, 0, 0, 0))

# ------------------------------------------------------------------ 3. "YUME" na pedra
# Face frontal da pedra: ~x 1090..1143, y 777..807. Letras gravadas (sombra + aresta clara).
DARK = (72, 44, 30)
LIGHT = (196, 152, 122)
GLYPHS = {
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"],
    "M": ["#.#", "###", "###", "#.#", "#.#"],
    "E": ["###", "#..", "##.", "#..", "###"],
}
x = 1101
y0 = 789
for ch in "YUME":
    rows = GLYPHS[ch]
    for ry, row in enumerate(rows):
        for rx, c in enumerate(row):
            if c == "#":
                blend_base(x + rx, y0 + ry, DARK, 0.62)
                # aresta iluminada (luz vem de cima/esquerda) um pixel abaixo/direita
                if ry == len(rows) - 1 or rows[ry + 1][rx] != "#":
                    blend_base(x + rx, y0 + ry + 1, LIGHT, 0.35)
    x += 5
# desgaste: alguns pixels da gravação mais fracos
for (wx, wy) in [(1103, 790), (1112, 793), (1117, 791)]:
    blend_base(wx, wy, DARK, 0.25)

# ------------------------------------------------------------------ 4. Baquetas
# No chão à direita da pedra (~x 1150..1185, y 806..822), na grama; parte coberta por folhas.
WOOD = (160, 118, 74, 255)
WOOD_D = (104, 72, 42, 255)
TIP = (196, 164, 118, 255)
def stick(x0, y0, x1, y1):
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        t = i / n
        sx = round(x0 + (x1 - x0) * t); sy = round(y0 + (y1 - y0) * t)
        put(sx, sy, WOOD)
        put(sx, sy + 1, WOOD_D)
    put(x1, y1, TIP); put(x1, y1 + 1, TIP)
stick(1086, 868, 1122, 858)
stick(1090, 873, 1126, 864)
# frondes da samambaia POR CIMA das baquetas: trechos ficam escondidos (folhas na frente)
for gy in range(854, 878):
    for gx in range(1084, 1130):
        r, g, b, _ = bpx[gx, gy]
        leaf = g > 140 and b < 100
        band = ((gx - 1084) // 5) % 3 == 1
        if leaf or band:
            put(gx, gy, (r, g, b, 255) if px[gx, gy][3] else (0, 0, 0, 0))

# ------------------------------------------------------------------ 5. Folhinha escondida
# Entre as samambaias (~x 14..34, y 686..704): 7 folíolos finos, verde um pouco mais escuro.
LEAF = (58, 112, 46, 255)
LEAF_D = (36, 78, 30, 255)
cx, cy = 24, 700
import math
for i, ang in enumerate([-90, -60, -120, -30, -150, -5, -175]):
    length = [9, 8, 8, 6, 6, 4, 4][i]
    for s in range(length):
        a = math.radians(ang)
        lx = round(cx + math.cos(a) * s); ly = round(cy + math.sin(a) * s)
        put(lx, ly, LEAF if s < length - 1 else LEAF_D)
        if s in (2, 4, 6) and length > 5:  # serrilhado
            put(lx + (1 if math.cos(a) >= 0 else -1), ly, LEAF_D)
put(cx, cy, LEAF_D)
for s in range(1, 4):
    put(cx, cy + s, LEAF_D)

ov.save(OUT)
print("ok", OUT)
