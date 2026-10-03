"""Xeque · fundos das telas de Tutorial e Resultado, tirados das próprias telas de referência
aprovadas (tools/xeque_src/telas/05_tutorial.jpg e 06_resultado.jpg), só sem o conteúdo, para o jogo
desenhar painéis, textos e botões vivos por cima nas mesmas posições:
  • tutorial_fundo.png: mesma moldura de madeira e pergaminho; o pergaminho por baixo dos painéis é
    preenchido com a cor do próprio pergaminho em volta (preenchimento por convolução normalizada).
  • resultado_fundo.png: mesmo fundo de raios; por baixo do conteúdo os raios são continuados na
    direção do raio (coordenadas polares em volta do centro dos raios)."""
import os
import numpy as np
from PIL import Image, ImageFilter
ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "tools/xeque_src/telas")
OUT = os.path.join(ROOT, "xeque/art/telas")
os.makedirs(OUT, exist_ok=True)

from scipy.ndimage import gaussian_filter

def blur(a, s):
    return gaussian_filter(a.astype(np.float32), s)

def nconv(img, mask, sigma):
    out = np.zeros_like(img)
    w = blur(mask.astype(np.float32), sigma)
    for c in range(3):
        out[..., c] = blur(img[..., c] * mask, sigma) / np.maximum(w, 1e-4)
    return out, w

# ---------------- tutorial
a = np.array(Image.open(os.path.join(SRC, "05_tutorial.jpg")).convert("RGB")).astype(np.float32)
X0, X1, Y0, Y1 = 118, 1802, 48, 1031                     # interior do pergaminho
inside = np.zeros(a.shape[:2], bool); inside[Y0:Y1, X0:X1] = True
p = (a[..., 0] > 205) & (a[..., 1] > 185) & (a[..., 2] > 135) & (a[..., 2] < 185)
p &= inside
# erode 5 px (tira bordas suaves de texto/painel)
m = p.copy()
for _ in range(5):
    m[1:] &= p[:-1]; m[:-1] &= p[1:]; m[:, 1:] &= p[:, :-1]; m[:, :-1] &= p[:, 1:]
    p = m.copy()
# modelo liso do pergaminho (polinômio de grau 4 em x,y, por canal) ajustado só nos pixels limpos
ys, xs = np.nonzero(m)
pick = np.random.default_rng(1).choice(len(xs), min(60000, len(xs)), replace=False)
xs, ys = xs[pick], ys[pick]
def basis(x, y):
    x = (x - 960.0) / 960.0; y = (y - 540.0) / 540.0
    return np.stack([x**i * y**j for i in range(5) for j in range(5 - i)], axis=-1)
B = basis(xs.astype(float), ys.astype(float))
coef = [np.linalg.lstsq(B, a[ys, xs, c], rcond=None)[0] for c in range(3)]
gy, gx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
GB = basis(gx.astype(float), gy.astype(float))
model = np.stack([GB @ coef[c] for c in range(3)], axis=-1)
out = a.copy()
core = np.zeros(a.shape[:2], bool); core[Y0 + 10:Y1 - 10, X0 + 10:X1 - 10] = True   # perto da moldura fica o original
out[core] = model[core]
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "tutorial_fundo.png"))
print("tutorial_fundo.png")

# ---------------- resultado
a = np.array(Image.open(os.path.join(SRC, "06_resultado.jpg")).convert("RGB")).astype(np.float32)
H, W = a.shape[:2]
mask = np.ones((H, W), bool)                               # True = fundo confiável
for (x, y, w_, h_) in [(660, 60, 600, 170), (400, 312, 320, 320), (440, 630, 250, 80), (230, 700, 660, 60),
                       (360, 770, 400, 100), (895, 262, 790, 130), (900, 392, 780, 415), (245, 915, 1430, 115)]:
    mask[y - 8:y + h_ + 8, x - 8:x + w_ + 8] = False
CX, CY = 960, 470
yy, xx = np.mgrid[0:H, 0:W]
ang = np.arctan2(yy - CY, xx - CX)
rr = np.hypot(xx - CX, yy - CY)
NA = 1440
ai = ((ang + np.pi) / (2 * np.pi) * NA).astype(int) % NA
# perfil dos raios por ângulo (só fundo confiável, longe do centro)
prof = np.zeros((NA, 3)); cnt = np.zeros(NA)
sel = mask & (rr > 250)
lum = a.mean(axis=2)
rbin = np.clip((rr / 20).astype(int), 0, 120)
# queda radial: média do brilho por raio
rad_mean = np.array([lum[sel & (rbin == i)].mean() if (sel & (rbin == i)).any() else np.nan for i in range(121)])
idx = np.arange(121); good = ~np.isnan(rad_mean)
rad_mean = np.interp(idx, idx[good], rad_mean[good])
norm = a / np.maximum(rad_mean[rbin][..., None], 1.0)
np.add.at(prof, ai[sel], norm[sel]); np.add.at(cnt, ai[sel], 1)
for c in range(3):
    v = prof[:, c] / np.maximum(cnt, 1)
    ok = cnt > 0
    prof[:, c] = np.interp(np.arange(NA), np.arange(NA)[ok], v[ok], period=NA)
back = prof[ai] * rad_mean[rbin][..., None]
# fundo confiável = original; conteúdo = raios reconstruídos; transição suave de ~14 px
wgt = gaussian_filter((~mask).astype(np.float32), 14)
wgt = np.maximum(wgt, (~mask).astype(np.float32) * 0.0)
wgt = np.where(~mask, np.maximum(wgt, 0.5) * 0 + 1.0, wgt * 2.0).clip(0, 1)
out = a * (1 - wgt[..., None]) + back * wgt[..., None]
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "resultado_fundo.png"))
print("resultado_fundo.png")
