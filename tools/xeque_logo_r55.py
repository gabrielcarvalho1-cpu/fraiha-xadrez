#!/usr/bin/env python3
"""R55 · Logo do XEQUE no PC (referência nova do dono): "XEQUE" dourado com relevo (X maior), contorno
escuro, coroa do pacote (xeque/art/interface/coroa.png) em cima e o pano vinho por trás. O subtítulo
(RODADA n · BLEFE DE CARTAS) é desenhado ao vivo pelo jogo. Gerado em 2x do tamanho de tela de
referência (1920x1080) para ficar nítido; saída: xeque/art/interface/logo_r55.png.
Uso: python3 tools/xeque_logo_r55.py"""
import io
import os
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "xeque/art/interface/logo_r55.png")
S = 2                      # escala sobre a tela de referência
W, H = 340 * S, 130 * S    # caixa do logo (px de tela 1920x1080: x 36..376, y 0..130)


def font(size):
    f = TTFont(os.path.join(ROOT, "account/fonts/Cinzel-Bold.woff")); f.flavor = None
    b = io.BytesIO(); f.save(b); b.seek(0)
    return ImageFont.truetype(b, size)


def letters_mask():
    """Desenha X grande + EQUE espaçado num rascunho grande e encaixa (escala uniforme) na caixa do logo."""
    big = Image.new("L", (W * 3, H * 2), 0)
    d = ImageDraw.Draw(big)
    fx, fe = font(int(90 * S / 0.7)), font(int(58 * S / 0.7))
    base = 160 * S
    x = 10 * S
    bx = d.textbbox((0, 0), "X", font=fx)
    d.text((x - bx[0], base - bx[3]), "X", font=fx, fill=255)
    x += bx[2] - bx[0] - 2 * S
    starts = []
    bh = d.textbbox((0, 0), "E", font=fe)
    for ch in "EQUE":
        bc = d.textbbox((0, 0), ch, font=fe)
        starts.append(x)
        d.text((x - bc[0], base - bh[3]), ch, font=fe, fill=255)
        x += (fe.getlength(ch) if ch != "Q" else bc[2] - bc[0] - 40 * S) + 3 * S   # Q: o rabo passa por baixo do U
    a = np.array(big)
    ys, xs = np.nonzero(a > 10)
    crop = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    room_w, room_h = 312 * S, 96 * S                  # caixa das letras (px de tela x2)
    k = min(room_w / crop.shape[1], room_h / crop.shape[0])
    cr = cv2.resize(crop, (int(crop.shape[1] * k), int(crop.shape[0] * k)), interpolation=cv2.INTER_AREA)
    m = np.zeros((H, W), np.float32)
    ox, oy = 14 * S, 116 * S - cr.shape[0] + int((ys.max() - base) * k) if False else 24 * S
    m[oy:oy + cr.shape[0], ox:ox + cr.shape[1]] = cr / 255.0
    m = cv2.dilate(m, np.ones((2 * S + 2, 2 * S + 2), np.uint8))   # traço encorpado (letras grossas da referência)
    q0 = ox + (starts[1] - xs.min()) * k                     # início do Q (coroa em cima dele)
    q1 = ox + (starts[2] - xs.min()) * k
    return m, (q0, q1)


def gold(h):
    t = np.linspace(0, 1, h)[:, None]
    top, mid, low = np.array([255, 246, 196]), np.array([246, 196, 84]), np.array([176, 112, 30])
    c = np.where(t < 0.45, top + (mid - top) * (t / 0.45), mid + (low - mid) * ((t - 0.45) / 0.55))
    return np.repeat(c[:, None, :], W, axis=1)


m, (ex0, ex1) = letters_mask()
out = np.zeros((H, W, 4), np.float32)
# pano vinho por trás (cantos suaves)
cloth = np.zeros((H, W), np.float32)
cv2.rectangle(cloth, (6 * S, 34 * S), (W - 4 * S, 124 * S), 1.0, -1)
cloth = cv2.GaussianBlur(cloth, (0, 0), 4 * S) * 0.92
t = np.linspace(0, 1, H)[:, None]
wine = np.array([70, 10, 18]) * (1 - t[..., None]) + np.array([34, 5, 9]) * t[..., None]
wine = np.repeat(wine, W, axis=1)
out[..., :3] = wine
out[..., 3] = cloth


def over(dst, rgb, a):
    a = a[..., None]
    da = dst[..., 3:4]
    na = a + da * (1 - a)
    dst[..., :3] = np.where(na > 0, (rgb * a + dst[..., :3] * da * (1 - a)) / np.maximum(na, 1e-6), dst[..., :3])
    dst[..., 3:4] = na


# sombra, contorno, ouro com relevo
sh = cv2.GaussianBlur(np.roll(np.roll(m, 4 * S, 0), 3 * S, 1), (0, 0), 3 * S)
over(out, np.zeros((H, W, 3)), sh * 0.75)
ol = cv2.dilate(m, np.ones((5 * S, 5 * S), np.uint8))
over(out, np.full((H, W, 3), (42, 18, 6), np.float32), ol)
g = gold(H)
hi = np.clip(m - np.roll(m, 2 * S, 0), 0, 1)          # borda de cima clara
lo = np.clip(m - np.roll(m, -2 * S, 0), 0, 1)         # borda de baixo escura
g = g * (1 - hi[..., None]) + np.array([255, 252, 228]) * hi[..., None]
g = g * (1 - lo[..., None] * 0.7) + np.array([110, 62, 14]) * lo[..., None] * 0.7
over(out, g, m)
out[..., 3] *= 255.0
img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
# coroa centrada sobre o "Q" (entre E e Q da referência)
crown = Image.open(os.path.join(ROOT, "xeque/art/interface/coroa.png")).convert("RGBA")
cw = 64 * S
crown = crown.resize((cw, int(crown.height * cw / crown.width)), Image.LANCZOS)
cx = int((ex0 + ex1) / 2)
img.alpha_composite(crown, (cx - cw // 2, 1 * S))
img.save(OUT, optimize=True)
print(OUT, img.size)
