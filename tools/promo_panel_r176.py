#!/usr/bin/env python3
"""R176 · painel PROMOÇÃO DO PEÃO a partir da arte enviada pelo dono (idêntica), com duas mudanças:
  1) o xadrez cinza "falso" do fundo (a imagem veio sem transparência) vira transparência de verdade;
  2) as 4 peças pintadas saem das casas (o jogo desenha as NOSSAS peças, da cor de quem promove).
Saída: ranked/art/promo_panel.png (RGBA) + as casas (px da arte) impressas para world.gd.
Uso: python3 tools/promo_panel_r176.py <arte_enviada.png>
"""
import sys
import numpy as np
import cv2
from PIL import Image

OUT = "ranked/art/promo_panel.png"
OUT_W = 1200
# casas (recorte x0..x1, y 420..722) e a coluna do meio de cada uma (px do recorte); linhas: 0..114 | 114..205 | 205..fim
TILES = [(245, 585, 118, 217), (592, 918, 117, 207), (928, 1252, 112, 206), (1262, 1596, 117, 214)]
Y0, Y1 = 420, 722
ROW1, ROW2 = 114, 205


def remove_fake_checker(rgb):
    """Fundo xadrez cinza ligado à borda → transparente (o resto da arte fica 100%)."""
    a = rgb.astype(int)
    sat = a.max(2) - a.min(2)
    val = a.mean(2)
    bgish = ((sat <= 12) & (val >= 100) & (val <= 215)).astype(np.uint8)
    h, w = bgish.shape
    mask = np.zeros((h + 2, w + 2), np.uint8)
    flood = bgish.copy()
    seeds = [(x, 0) for x in range(0, w, 7)] + [(x, h - 1) for x in range(0, w, 7)] + \
            [(0, y) for y in range(0, h, 7)] + [(w - 1, y) for y in range(0, h, 7)]
    out = np.zeros((h, w), np.uint8)
    for sx, sy in seeds:
        if bgish[sy, sx] and not out[sy, sx]:
            m = np.zeros((h + 2, w + 2), np.uint8)
            cv2.floodFill(flood, m, (sx, sy), 2, loDiff=0, upDiff=0, flags=4 | (1 << 8) | cv2.FLOODFILL_MASK_ONLY)
            out |= m[1:-1, 1:-1]
    bg = out.astype(bool)
    # 2ª passada: o xadrez "tingido" pelo brilho das peças douradas (pouca cor) junto do fundo também sai
    loose = (sat <= 40) & (val >= 90) & (val <= 230)
    for _ in range(40):
        grown = cv2.dilate(bg.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool) & loose
        if (grown & ~bg).sum() == 0: break
        bg |= grown
    # borda suave: 1 px de transição
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    alpha = cv2.erode(alpha, np.ones((3, 3), np.uint8))
    alpha = cv2.GaussianBlur(alpha, (3, 3), 0)
    return alpha


def piece_mask(t):
    """Peça pintada na casa: componentes saturados (creme/dourado) longe da moldura, preenchidos + contorno."""
    h, w = t.shape[:2]
    a = t.astype(int)
    sat = a.max(2) - a.min(2)
    hi = (sat > 18).astype(np.uint8) * 255
    hi = cv2.morphologyEx(hi, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, lab, stats, cent = cv2.connectedComponentsWithStats(hi)
    m = np.zeros((h, w), np.uint8)
    for i in range(1, n):
        x, y, bw, bh, area = stats[i]
        if area < 40: continue
        cx, cy = cent[i]
        if 40 < cx < w - 40 and 30 < cy < h - 26 and x > 26 and x + bw < w - 24 and y > 22 and y + bh < h - 16:
            m[lab == i] = 255
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(m, cnts, -1, 255, -1)
    return cv2.dilate(m, np.ones((13, 13), np.uint8))


def clean_template(img):
    """Casa limpa (sem peça) montada só com casas SEM peça da casa do BISPO (a peça mais estreita):
    cinza = cantos de cima (TL/TR), branca = meio-esquerda/direita (ML/MR); embaixo, os cantos de cima espelhados."""
    x0, x1, cx0, cx1 = TILES[2]
    t = img[Y0:Y1, x0:x1].copy()
    h, w = t.shape[:2]
    L, R, T, B = 22, w - 18, 18, h - 12
    cols, rows = [L, cx0, cx1, R], [T, ROW1, ROW2, B]
    m = 7   # só o miolo de cada casa (as bordas entre casas são borradas na arte)
    cell = lambda c, r: t[rows[r] + m:rows[r + 1] - m, cols[c] + m:cols[c + 1] - m].copy()
    TL, TR, ML, MR = cell(0, 0), cell(2, 0), cell(0, 1), cell(2, 1)
    G = t[T + 34:ROW1 - m, L + 34:cx0 - m].copy()   # cinza sem o ornamento dourado do canto (para a casa do meio)
    plan = [[TL, cv2.flip(ML, 1), TR],
            [ML, cv2.flip(G, -1), MR],
            [cv2.flip(TL, 0), cv2.flip(MR, -1), cv2.flip(TR, 0)]]
    out = np.zeros((B - T, R - L, 3), np.uint8)
    for r in range(3):
        for c in range(3):
            ww, hh = cols[c + 1] - cols[c], rows[r + 1] - rows[r]
            out[rows[r] - T:rows[r + 1] - T, cols[c] - L:cols[c + 1] - L] = cv2.resize(plan[r][c], (ww, hh), interpolation=cv2.INTER_CUBIC)
    return out


def clean_tile(img, tpl, x0, x1):
    t = img[Y0:Y1, x0:x1]
    h, w = t.shape[:2]
    L, R, T, B = 22, w - 18, 18, h - 12
    a = t.astype(int)
    sat = a.max(2) - a.min(2)
    pm = piece_mask(t) > 0
    clean = cv2.resize(tpl, (R - L, B - T), interpolation=cv2.INTER_CUBIC)
    region = t[T:B, L:R]
    # tudo vira casa limpa, menos os ornamentos dourados dos 4 cantos da moldura (que invadem a casa)
    keep = np.zeros((B - T, R - L), bool)
    cw = 40
    for ys in (slice(0, cw), slice(B - T - cw, B - T)):
        for xs in (slice(0, cw), slice(R - L - cw, R - L)):
            keep[ys, xs] = sat[T:B, L:R][ys, xs] > 20
    keep = cv2.dilate(keep.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    use = ~keep
    use = cv2.GaussianBlur(use.astype(np.float32), (5, 5), 0)[..., None]
    region[:] = (clean * use + region * (1 - use)).astype(np.uint8)


def main(src):
    rgb = np.array(Image.open(src).convert("RGB"))
    alpha = remove_fake_checker(rgb)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    tpl = clean_template(bgr.copy())
    for x0, x1, _, _ in TILES:
        clean_tile(bgr, tpl, x0, x1)
    res = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    im = Image.fromarray(np.dstack([res, alpha]))
    s = OUT_W / im.width
    im.resize((OUT_W, round(im.height * s)), Image.LANCZOS).save(OUT)
    print("ok", im.width, im.height)
    for i, (x0, x1, _, _) in enumerate(TILES):
        print("casa", i, "x", x0 + 22, x1 - 20, "y", Y0 + 20, Y1 - 14)


if __name__ == "__main__":
    main(sys.argv[1])
