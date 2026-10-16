#!/usr/bin/env python3
"""R135 · LIGAS na partida com o layout da Madeira: casas e peças de cada liga em PIXEL ART + enfeites dourados dos cantos.
- casas: recortadas das artes de referência do dono (tools/art/ligas_ref/<liga>.png), reduzidas para 48 px por casa,
  paleta curta (sem degradê), ampliadas 2x sem suavizar → cosmetics/ligas_pixel/<liga>_casas.png (768x768).
- peças: as do jogo para a liga (atlas pieces_path), reduzidas para pixel art (altura ~ metade das peças da Madeira),
  paleta curta e contorno escuro de 1 px, ampliadas 2x → cosmetics/ligas_pixel/<liga>_pecas.png + .json (regiões).
- cantos: os 4 enfeites dourados da moldura recortados de ranked/art/board_pc.png → cosmetics/ligas_pixel/cantos.png +
  cantos.json (posição em px da arte; a grade tem 693.5 px a partir de (382, 145.5)). Ficam POR CIMA das casas.
Uso: python3 tools/art/ligas_pixel_r135.py"""
import os, re, json
import numpy as np
from PIL import Image
from scipy import ndimage as nd
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "cosmetics/ligas_pixel")
os.makedirs(OUT, exist_ok=True)
# grade (x0, lado_x, y0, lado_y) das casas em cada arte de referência (1254x1254)
GRID = {"grande_mestre": (114, 1023, 121, 1013), "challenger": (116, 1020, 109, 1022), "esmeralda": (97, 1058, 106, 1055),
        "mestre": (103, 1047, 111, 1045), "diamante": (100, 1054, 108, 1026), "platina": (97, 1059, 103, 1063),
        "silver": (128, 995, 115, 996), "gold": (116, 1020, 98, 1022), "iron": (95, 1062, 102, 1048), "bronze": (107, 1039, 103, 1023)}
PX = 48
src = open(os.path.join(ROOT, "cosmetics/theme_catalog.gd")).read()
PIECES = {m.group(1): m.group(2) for m in re.finditer(r'"id":"(\w+)".*?"pieces_path":"res://([^"]+)"', src)}
HEIGHT = {"P": 30, "R": 34, "N": 35, "B": 36, "Q": 37, "K": 37}   # ~metade das peças pixel art da Madeira (x2 na tela)

def quant(im, colors):
    rgb = im.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    if im.mode == "RGBA":
        a = im.getchannel("A").point(lambda v: 255 if v > 110 else 0)
        rgb = rgb.convert("RGBA"); rgb.putalpha(a)
    return rgb

def tiles(lid):
    x0, sx, y0, sy = GRID[lid]
    im = Image.open(os.path.join(ROOT, "tools/art/ligas_ref", lid + ".png")).convert("RGB")
    T = 160
    cas = Image.new("RGB", (8 * T, 8 * T))
    src_row = {0: 2, 1: 3, 2: 2, 3: 3, 4: 4, 5: 5, 6: 4, 7: 5}   # casas vazias da arte (sem peças), mantendo o xadrez
    for y in range(8):
        for x in range(8):
            r = src_row[y]
            cell = im.crop((round(x0 + x * sx / 8), round(y0 + r * sy / 8), round(x0 + (x + 1) * sx / 8), round(y0 + (r + 1) * sy / 8)))
            cas.paste(cell.resize((T, T), Image.LANCZOS), (x * T, y * T))
    small = quant(cas.resize((8 * PX, 8 * PX), Image.BOX), 32)
    small.resize((16 * PX, 16 * PX), Image.NEAREST).save(os.path.join(OUT, lid + "_casas.png"), optimize=True)

def outline(sp):
    w, h = sp.size
    c = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0)); c.paste(sp, (1, 1))
    a = np.asarray(c).copy(); al = a[..., 3] > 0
    ring = nd.binary_dilation(al, structure=np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]])) & ~al
    a[ring] = (18, 12, 8, 255)
    return Image.fromarray(a)

def pieces(lid):
    at = Image.open(os.path.join(ROOT, PIECES[lid])).convert("RGBA")
    cw, ch = at.width // 6, at.height // 2
    sprites = {}
    for row, col in [(0, "w"), (1, "b")]:
        for c, k in enumerate("PRNBQK"):
            box = [c * cw, row * ch, (c + 1) * cw, (row + 1) * ch]
            if lid == "iron" and row == 1 and c < 5: box[1] += 24
            cell = at.crop(box); a = np.asarray(cell)[..., 3]; ys, xs = np.where(a > 40)
            sp = cell.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            h = HEIGHT[k]; w = max(1, round(sp.width * h / sp.height))
            px = outline(quant(sp.resize((w, h), Image.BOX), 28))
            sprites[col + k] = px.resize((px.width * 2, px.height * 2), Image.NEAREST)
    W = sum(s.width for s in sprites.values()) + 4 * len(sprites); H = max(s.height for s in sprites.values())
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0)); x = 0; rects = {}
    for code, s in sprites.items():
        atlas.paste(s, (x, H - s.height)); rects[code] = [x, H - s.height, s.width, s.height]; x += s.width + 4
    atlas.save(os.path.join(OUT, lid + "_pecas.png"), optimize=True)
    json.dump(rects, open(os.path.join(OUT, lid + "_pecas.json"), "w"))

def corners():
    A = np.asarray(Image.open(os.path.join(ROOT, "ranked/art/board_pc.png")).convert("RGB")).astype(int)
    CAS = np.asarray(Image.open(os.path.join(ROOT, "visual_v018/casas_madeira.png")).convert("RGB").resize((694, 694), Image.LANCZOS)).astype(int)
    bx, by, W = 382, 146, 48
    pieces_out = []; info = []
    for cx, cy in [(bx, by), (bx + 694, by), (bx, by + 694), (bx + 694, by + 694)]:
        x0, y0 = cx - W, cy - W
        reg = A[y0:y0 + 2 * W, x0:x0 + 2 * W]
        yy, xx = np.mgrid[0:2 * W, 0:2 * W]
        X, Y = x0 + xx - bx, y0 + yy - by
        inside = (X >= 0) & (X < 694) & (Y >= 0) & (Y < 694)
        tilelike = np.zeros(reg.shape[:2], bool)
        tilelike[inside] = np.abs(reg[inside] - CAS[Y[inside], X[inside]]).sum(-1) < 75
        r, g, b = reg[..., 0], reg[..., 1], reg[..., 2]
        gold = (r > 150) & (g > 60) & (b < 120) & (r - b > 90) & ~tilelike
        green = (g > r + 10) & (g > b + 10)
        core = nd.binary_dilation(gold, iterations=2) & ~tilelike & ~green
        lab, n = nd.label(core); keep = np.zeros_like(core)
        for k in range(1, n + 1):
            ys, xs = np.where(lab == k)
            if len(ys) > 120 and np.min(np.hypot(xs - W, ys - W)) < 22: keep |= lab == k
        m = nd.binary_fill_holes(keep) & ~tilelike & ~green
        m = nd.binary_opening(m, iterations=1)
        m = nd.binary_fill_holes(nd.binary_closing(m, structure=np.ones((9, 9))))
        m = nd.binary_opening(m, structure=np.ones((5, 5)))
        c = Image.fromarray(reg.astype("uint8")).convert("RGBA"); c.putalpha(Image.fromarray((m * 255).astype("uint8")))
        pieces_out.append(c); info.append([x0, y0])
    sheet = Image.new("RGBA", (4 * 96, 96), (0, 0, 0, 0))
    for i, c in enumerate(pieces_out): sheet.paste(c, (i * 96, 0))
    sheet.save(os.path.join(OUT, "cantos.png"), optimize=True)
    json.dump({"board": [382.0, 145.5, 693.5], "size": 96, "at": info}, open(os.path.join(OUT, "cantos.json"), "w"))

for lid in GRID:
    tiles(lid); pieces(lid); print(lid)
corners()


# --- o export Web só leva recursos: as regiões vão também num script de dados (cosmetics/league_pixel_data.gd)
def write_gd_data():
    import glob
    pecas = {}
    for p in sorted(glob.glob(os.path.join(OUT, "*_pecas.json"))):
        pecas[os.path.basename(p)[:-len("_pecas.json")]] = json.load(open(p))
    cantos = json.load(open(os.path.join(OUT, "cantos.json")))
    dst = os.path.join(os.path.dirname(OUT.rstrip("/")), "league_pixel_data.gd")
    with open(dst, "w") as f:
        f.write("extends RefCounted\n## R135 · GERADO por tools/art/ligas_pixel_r135.py — regiões das peças e dos cantos (não editar à mão)\n")
        f.write("const PECAS := " + json.dumps(pecas, sort_keys=True) + "\n")
        f.write("const CANTOS := " + json.dumps(cantos) + "\n")

if __name__ == "__main__":
    write_gd_data()
