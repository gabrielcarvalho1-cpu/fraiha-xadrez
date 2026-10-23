#!/usr/bin/env python3
"""R177j · resultado do XEQUE no celular EM PÉ = as artes de referência do dono (941x1672), iguais.

Entrada: as duas artes (vitória azul / derrota vermelha) em tools/ref_r177j/{vitoria,derrota}.png.
Saída:   xeque/art/telas/r177p_{vitoria,derrota}.png  (941 x 1672+2*EXT, RGBA)
  - textos dinâmicos apagados (nome, "VOCÊ FICOU EM Nº LUGAR", faixa do xeque-mate, nomes/BOT/legendas da classificação)
    — o jogo escreve por cima, nos mesmos lugares (xeque_view.gd · P177);
  - retrato e as 4 miniaturas viram buracos transparentes (o avatar é desenhado por baixo); as joias da moldura
    que entram no retrato continuam opacas;
  - EXT px acima e abaixo: a própria arte espelhada, desfocada e escurecida aos poucos (celulares mais altos que 9:16).
Uso: python3 tools/visual_r177j_cel.py [--preview DIR]
"""
import os, sys
import numpy as np
import cv2
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXT = 260

# coordenadas na arte (px) — medidas nas referências
SPEC = {
    "vitoria": {
        "portrait": (298, 344, 640, 644),
        "jewels": [(280, 494), (655, 494), (467, 306), (470, 655)],
        "thumbs": [(158, 1033, 248, 1118), (158, 1141, 248, 1226), (158, 1249, 248, 1334), (158, 1358, 248, 1447)],
        "text": [(306, 668, 632, 746, 110), (240, 768, 700, 806, 110), (212, 928, 852, 980, 150),
                 (270, 1040, 780, 1077, 105), (270, 1080, 780, 1110, 95),
                 (270, 1148, 780, 1188, 105), (270, 1190, 780, 1219, 95),
                 (270, 1256, 780, 1294, 105), (270, 1298, 780, 1328, 95),
                 (270, 1365, 780, 1404, 105), (270, 1407, 780, 1438, 95)],
    },
    "derrota": {
        "portrait": (311, 336, 626, 636),
        "jewels": [(289, 491), (647, 491), (470, 305), (470, 650)],
        "thumbs": [(162, 1039, 248, 1124), (162, 1144, 248, 1230), (162, 1248, 248, 1334), (162, 1356, 248, 1443)],
        "text": [(316, 668, 622, 746, 110), (240, 764, 700, 800, 110), (212, 928, 852, 984, 150),
                 (270, 1040, 780, 1077, 105), (270, 1078, 780, 1108, 95),
                 (270, 1146, 780, 1184, 105), (270, 1186, 780, 1215, 95),
                 (270, 1250, 780, 1290, 105), (270, 1293, 780, 1321, 95),
                 (270, 1360, 780, 1398, 105), (270, 1401, 780, 1430, 95)],
    },
}


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def erase_text(img, rects):
    """apaga o texto claro dentro de cada retângulo: preenche com a média ponderada (gaussiana) do fundo ao redor."""
    out = img.astype(np.float32).copy()
    L = lum(out)
    for (x0, y0, x1, y1, th) in rects:
        m = np.zeros(L.shape, bool)
        m[y0:y1, x0:x1] = L[y0:y1, x0:x1] > th
        m = ndimage.binary_dilation(m, iterations=4)
        clip = np.zeros(L.shape, bool)
        clip[y0 - 2:y1 + 2, x0 - 2:x1 + 2] = True
        m &= clip
        if not m.any():
            continue
        px0, py0, px1, py1 = max(0, x0 - 40), max(0, y0 - 40), min(out.shape[1], x1 + 40), min(out.shape[0], y1 + 40)
        sub = out[py0:py1, px0:px1]
        ms = m[py0:py1, px0:px1]
        w = (~ms).astype(np.float32)
        # o fundo é quase liso na horizontal (placas, linhas da tabela): borra mais na horizontal
        fill = np.zeros_like(sub)
        for sx, sy in [(18, 3), (30, 6), (60, 12)]:
            num = cv2.GaussianBlur(sub * w[..., None], (0, 0), sigmaX=sx, sigmaY=sy)
            den = cv2.GaussianBlur(w, (0, 0), sigmaX=sx, sigmaY=sy)[..., None]
            f = num / np.maximum(den, 1e-4)
            ok = (den[..., 0] > 0.05) & (fill.sum(-1) == 0)
            fill[ok] = f[ok]
        # um pouco da textura do lugar (ruído fino) para não ficar "plástico"
        rng = np.random.default_rng(7)
        fill += rng.normal(0, 2.0, fill.shape).astype(np.float32)
        sub[ms] = fill[ms]
        out[py0:py1, px0:px1] = sub
        # emenda suave
        edge = ndimage.binary_dilation(m, iterations=2) & ~ndimage.binary_erosion(m, iterations=1)
        bl = cv2.GaussianBlur(out, (5, 5), 0)
        out[edge] = bl[edge]
    return np.clip(out, 0, 255).astype(np.uint8)


def jewel_mask(img, hole, jewels):
    """dentro do buraco do retrato: o que é moldura/joia (fica opaco)."""
    a = img.astype(np.int32)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    gold = (R > 140) & (G > 70) & (R - B > 70)
    gem = ((B > 120) & (B - R > 40) & (lum(a) > 70)) | ((R > 150) & (G < 60) & (B < 80))
    bright = lum(a) > 235
    F = gold | gem | bright
    x0, y0, x1, y1 = hole
    H, W = F.shape
    yy, xx = np.mgrid[0:H, 0:W]
    out = np.zeros((H, W), bool)
    for (cx, cy) in jewels:
        near = (np.abs(xx - cx) + np.abs(yy - cy)) < 46
        lab, n = ndimage.label(F & near)
        # componentes que tocam a borda do buraco (vêm da moldura) ou o centro da joia
        keep = set()
        ring = np.zeros((H, W), bool)
        ring[y0 - 3:y1 + 3, x0 - 3:x1 + 3] = True
        ring[y0 + 1:y1 - 1, x0 + 1:x1 - 1] = False
        for k in np.unique(lab[ring & (lab > 0)]):
            keep.add(int(k))
        c = lab[cy, cx]
        if c > 0:
            keep.add(int(c))
        comp = np.isin(lab, list(keep)) if keep else np.zeros((H, W), bool)
        comp = ndimage.binary_closing(comp, iterations=2)
        comp = ndimage.binary_fill_holes(comp)
        comp = ndimage.binary_dilation(comp, iterations=1)   # o contorno escuro
        out |= comp & near
    return out


def extend(rgb):
    """EXT px acima e abaixo: só o cenário da beira da arte (sem título nem botões), espichado, desfocado e escurecendo."""
    H, W, _ = rgb.shape
    def band(strip, flip, dark=0.72):
        st = strip[::-1] if flip else strip
        b = cv2.resize(st, (W, EXT), interpolation=cv2.INTER_CUBIC).astype(np.float32)
        b1 = cv2.GaussianBlur(b, (0, 0), sigmaX=10, sigmaY=8)
        b2 = cv2.GaussianBlur(b, (0, 0), sigmaX=40, sigmaY=30)
        out = np.empty_like(b)
        for i in range(EXT):
            t = (i + 1) / EXT   # 0 junto da arte → 1 na borda
            row = b[i] * max(0.0, 1 - 3 * t) + b1[i] * min(1.0, 3 * t) * (1 - t) + b2[i] * t
            if t < 1 / 3:
                row = b[i] * (1 - 3 * t) + b1[i] * (3 * t)
            else:
                u = (t - 1 / 3) / (2 / 3)
                row = b1[i] * (1 - u) + b2[i] * u
            out[i] = row * (1.0 - dark * t ** 1.1)
        return out
    top = band(rgb[0:34], True, 0.85)[::-1]            # a beira de cima, espelhada e espichada para cima
    bot = band(rgb[H - 64:H], True)               # a beira de baixo (chão, abaixo dos botões)
    return np.concatenate([top, rgb.astype(np.float32), bot], 0).clip(0, 255).astype(np.uint8)


def build(key, src):
    rgb = cv2.cvtColor(cv2.imread(src, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
    s = SPEC[key]
    clean = erase_text(rgb, s["text"])
    alpha = np.full(rgb.shape[:2], 255, np.uint8)
    x0, y0, x1, y1 = s["portrait"]
    keep = jewel_mask(rgb, s["portrait"], s["jewels"])
    hole = np.zeros(alpha.shape, bool)
    hole[y0:y1, x0:x1] = True
    alpha[hole & ~keep] = 0
    for (a0, b0, a1, b1) in s["thumbs"]:
        alpha[b0:b1, a0:a1] = 0
    ext = extend(clean)
    A = np.concatenate([np.full((EXT, rgb.shape[1]), 255, np.uint8), alpha, np.full((EXT, rgb.shape[1]), 255, np.uint8)], 0)
    rgba = np.dstack([ext, A])
    out = os.path.join(ROOT, "xeque/art/telas/r177p_%s.png" % key)
    cv2.imwrite(out, cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA), [cv2.IMWRITE_PNG_COMPRESSION, 9])
    print("ok", out, rgba.shape)
    return rgba


if __name__ == "__main__":
    prev = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else ""
    for key in ("vitoria", "derrota"):
        rgba = build(key, os.path.join(ROOT, "tools/ref_r177j/%s.png" % key))
        if prev:
            bg = np.zeros_like(rgba[..., :3]); bg[:] = (255, 0, 255)
            a = rgba[..., 3:4] / 255.0
            cv2.imwrite(os.path.join(prev, "prev_%s.png" % key), cv2.cvtColor((rgba[..., :3] * a + bg * (1 - a)).astype(np.uint8), cv2.COLOR_RGB2BGR))
