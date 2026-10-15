#!/usr/bin/env python3
"""R113 · troca o VERDE dos painéis e botões pelo AZUL do jogo (o mesmo azul aprovado no FRAIHA PREMIUM).

Só mexe nos tons verde-azulados das molduras/painéis (matiz ~125°–180°), com transição suave nas bordas
da faixa; folhagem (verde-amarelado, matiz < 115°), dourado, vermelho e azul ficam como estão.
Uso: python3 tools/art/verde_para_azul.py [--dry] arquivo.png ...   (grava por cima; o original fica no git)
"""
import sys
import numpy as np
from PIL import Image

H_TARGET = 220.0           # azul-marinho do jogo (acc_bottom 0e1f45 / acc_top 2f5aa8)
LO0, LO1 = 112.0, 125.0    # entrada suave da faixa
HI1, HI0 = 178.0, 190.0    # saída suave da faixa
S_MIN = 0.10               # quase cinza não muda
V_LIFT = 0.45              # compensação de brilho (mais nos tons escuros)

def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1); mn = rgb.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r); gm = m & (mx == g) & ~rm; bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = ((b - r)[gm] / d[gm]) + 2
    h[bm] = ((r - g)[bm] / d[bm]) + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx

def hsv_to_rgb(h, s, v):
    h = (h % 360.0) / 60.0
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m, 0] = a[m]; out[m, 1] = b[m]; out[m, 2] = c[m]
    return out

def convert(path, dry=False):
    im = Image.open(path)
    mode = im.mode
    rgba = np.asarray(im.convert('RGBA')).astype(float) / 255.0
    rgb = rgba[..., :3]
    h, s, v = rgb_to_hsv(rgb)
    w = np.clip((h - LO0) / (LO1 - LO0), 0, 1) * np.clip((HI0 - h) / (HI0 - HI1), 0, 1)
    w *= np.clip((s - S_MIN) / 0.08, 0, 1)
    # o azul parece mais escuro que o verde no mesmo brilho: clareia um pouco os tons escuros
    v2 = np.clip(v * (1.0 + V_LIFT * (1.0 - v)), 0, 1)
    new = hsv_to_rgb(np.full_like(h, H_TARGET), s, v2)
    out = rgb * (1 - w[..., None]) + new * w[..., None]
    changed = float((w > 0.5).mean())
    if not dry:
        res = np.concatenate([out, rgba[..., 3:]], -1)
        img = Image.fromarray(np.clip(res * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')
        if mode != 'RGBA' and not (mode in ('P', 'LA') and 'transparency' in im.info): img = img.convert('RGB')
        img.save(path, optimize=True)
    return changed

if __name__ == '__main__':
    dry = '--dry' in sys.argv
    for p in [a for a in sys.argv[1:] if not a.startswith('--')]:
        print('%5.1f%%  %s' % (100 * convert(p, dry), p))
