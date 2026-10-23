#!/usr/bin/env python3
"""R178e · BOTÃO DO PASSE = a arte do dono (tools/ref_r178_pass_button.png, 2172x724), idêntica.
Saídas (recortadas na caixa da arte, 2035x501):
  economy/art/pass_button_plate.png — a arte SEM a frase de baixo, SEM o preenchimento roxo da barra e SEM o número
                                      do nível (o jogo escreve/desenha esses três, que mudam)
  economy/art/pass_button_fill.png  — o preenchimento roxo da barra (corpo + ponta), esticado pelo jogo até o progresso
"""
import os
import numpy as np
import cv2
from scipy import ndimage
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOX = (67, 103, 2103, 605)            # x0, y0, x1, y1 da arte (fora é transparente)
SUB = (515, 338, 1650, 424)           # frase "Temporada de Outubro · faltam 8 dias"
BAR = (520, 438, 1704, 491)           # miolo da barra (entre as bordas douradas)
FILL = (520, 438, 1062, 491)          # o roxo da referência
NUM = (1845, 350, 1950, 458)          # o "7" do escudo
src = cv2.imread(os.path.join(ROOT, "tools/ref_r178_pass_button.png"), cv2.IMREAD_UNCHANGED)
rgb = src[..., :3].astype(np.float32)
A = src[..., 3]
L = rgb @ np.array([0.114, 0.587, 0.299], np.float32)   # BGR

def fill_bg(img, mask, box, sx=30, sy=4):
    x0, y0, x1, y1 = box
    px0, py0, px1, py1 = x0 - 40, y0 - 30, x1 + 40, y1 + 30
    sub = img[py0:py1, px0:px1]
    ms = mask[py0:py1, px0:px1]
    w = (~ms).astype(np.float32)
    out = np.zeros_like(sub)
    for s in [(sx, sy), (sx * 2, sy * 2), (sx * 4, sy * 4)]:
        num = cv2.GaussianBlur(sub * w[..., None], (0, 0), sigmaX=s[0], sigmaY=s[1])
        den = cv2.GaussianBlur(w, (0, 0), sigmaX=s[0], sigmaY=s[1])[..., None]
        f = num / np.maximum(den, 1e-4)
        ok = (den[..., 0] > 0.05) & (out.sum(-1) == 0)
        out[ok] = f[ok]
    out += np.random.default_rng(5).normal(0, 1.5, out.shape).astype(np.float32)
    sub[ms] = out[ms]

clean = rgb.copy()
# 1) frase: letras claras (creme) sobre o painel azul
x0, y0, x1, y1 = SUB
m = np.zeros(L.shape, bool)
m[y0:y1, x0:x1] = L[y0:y1, x0:x1] > 105
m = ndimage.binary_dilation(m, iterations=4)
mm = np.zeros_like(m); mm[y0 - 4:y1 + 4, x0 - 4:x1 + 4] = True; m &= mm
fill_bg(clean, m, SUB)
# 2) número do nível: dourado sobre o roxo do escudo
x0, y0, x1, y1 = NUM
m = np.zeros(L.shape, bool)
m[y0:y1, x0:x1] = (L[y0:y1, x0:x1] > 70) | (L[y0:y1, x0:x1] < 36)
m = ndimage.binary_dilation(m, iterations=3)
mm = np.zeros_like(m); mm[y0 - 3:y1 + 3, x0 - 3:x1 + 3] = True; m &= mm
fill_bg(clean, m, NUM, 6, 6)
# 3) barra: guarda o roxo e põe o fundo vazio da barra (perfil de cada linha tirado da parte vazia)
fx0, fy0, fx1, fy1 = FILL
fill_img = src[fy0:fy1, fx0:fx1].copy()
bx0, by0, bx1, by1 = BAR
B, G, R = rgb[..., 0], rgb[..., 1], rgb[..., 2]
purple = (B > 110) & (R > 80) & (G < 110) & (B - G > 50)
purple = ndimage.binary_dilation(purple, iterations=3)
for y in range(by0, by1):
    ref = np.median(rgb[y, 1250:1650], axis=0)
    if ref[2] > 150 and ref[1] > 90 and ref[0] < 120: continue   # linha da borda dourada
    xs = np.arange(bx0, fx1 + 8)
    keep = (R[y, xs] > 150) & (G[y, xs] > 90) & (B[y, xs] < 110) & ~purple[y, xs]   # ouro da ponta esquerda
    clean[y, xs[~keep]] = ref
# máscara do roxo (alfa do preenchimento): só o que era roxo
fa = purple[fy0:fy1, fx0:fx1].astype(np.float32)
fa = cv2.GaussianBlur(fa, (0, 0), 0.8)
fill_rgba = np.dstack([fill_img[..., :3], (fa * 255).astype(np.uint8)])
X0, Y0, X1, Y1 = BOX
plate = np.dstack([np.clip(clean, 0, 255).astype(np.uint8), A])[Y0:Y1, X0:X1]
cv2.imwrite(os.path.join(ROOT, "economy/art/pass_button_plate.png"), plate, [cv2.IMWRITE_PNG_COMPRESSION, 9])
cv2.imwrite(os.path.join(ROOT, "economy/art/pass_button_fill.png"), fill_rgba, [cv2.IMWRITE_PNG_COMPRESSION, 9])
print("ok plate", plate.shape, "fill", fill_rgba.shape)
