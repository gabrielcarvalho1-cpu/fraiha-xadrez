#!/usr/bin/env python3
"""R122 · molduras dos botões do topo da Home com o miolo AZUL (o mesmo azul dos botões do menu).
Lê as molduras recortadas da arte (R113), acha o miolo escuro por preenchimento a partir do centro
(tudo que não é dourado) e pinta com um degradê azul-marinho, guardando a textura fina da arte.
Uso: python3 tools/art/moldura_topo_azul_r122.py   (gera *_azul.png ao lado das originais)"""
from collections import deque
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "ui_v022/assets/r113"
TOP, BOT = (6, 34, 92), (1, 17, 52)       # azul do menu (claro em cima, escuro embaixo)

def gold(p):
    r, g, b, a = p
    return a > 0 and r > 95 and r > b + 35

def paint(name):
    im = Image.open(SRC / f"{name}.png").convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = [[False] * h for _ in range(w)]
    q = deque([(w // 2, h // 2)])
    inner = []
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or seen[x][y] or gold(px[x, y]): continue
        seen[x][y] = True
        inner.append((x, y))
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    ys = [y for _, y in inner]
    y0, y1 = min(ys), max(ys)
    for x, y in inner:
        r, g, b, a = px[x, y]
        t = (y - y0) / max(1, y1 - y0)
        base = [TOP[i] + (BOT[i] - TOP[i]) * t for i in range(3)]
        lum = (r + g + b) / 3.0
        k = 0.85 + 0.6 * (lum / 40.0)            # a granulação da arte continua aparecendo
        c = [max(0, min(255, int(v * k))) for v in base]
        px[x, y] = (c[0], c[1], c[2], 255)
    # brilho de chanfro: 1ª linha do miolo um pouco mais clara
    for x, y in inner:
        if y == y0 or y == y0 + 1:
            r, g, b, a = px[x, y]
            px[x, y] = (min(255, r + 10), min(255, g + 22), min(255, b + 40), 255)
    out = SRC / f"{name}_azul.png"
    im.save(out)
    print(out.relative_to(ROOT), len(inner), "px de miolo")

for n in ["moldura_botao_topo_pc", "moldura_botao_topo_cel"]: paint(n)
