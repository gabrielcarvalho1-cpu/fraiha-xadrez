#!/usr/bin/env python3
"""R124 · artes de EMPATE, feitas a partir das de derrota/vitória (mesma moldura e estilo):
  - ranked/art/desk_draw_casual.png, desk_draw_ranked.png, desk_bot_draw.png: o título "DERROTA" é apagado
    (inpaint) e "EMPATE" é escrito em PRATA (degradê claro → aço) com contorno escuro, no mesmo tamanho;
  - presentation_v019/results/draw.png (tela cinematográfica): a de VITÓRIA em prata/aço, com "EMPATE!".
Uso: python3 tools/art/empate_r124.py"""
import os
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
FONT = os.path.join(ROOT, "account/fonts/Cinzel-Bold.woff")
SILVER_TOP, SILVER_BOT = (250, 252, 255), (150, 172, 205)

def text_mask(a, box):
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1].astype(int)
    r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
    warm = (r > 120) & (r - b > 45)              # letras (salmão / dourado) e o brilho delas
    dark = (r + g + b < 60) & (r >= b - 6)       # contorno escuro/marrom das letras
    m = np.zeros(a.shape[:2], np.uint8)
    m[y0:y1, x0:x1] = ((warm | dark) * 255).astype(np.uint8)
    return cv2.dilate(m, np.ones((7, 7), np.uint8))

def write(img, text, cx, cy, cap_h, grad=(SILVER_TOP, SILVER_BOT), outline=(18, 22, 34), glow=None):
    size = int(cap_h * 1.42)
    font = ImageFont.truetype(FONT, size)
    d = ImageDraw.Draw(img)
    bb = d.textbbox((0, 0), text, font=font, anchor="ls")
    w, h = bb[2] - bb[0], -bb[1]
    x, base = int(cx - w / 2), int(cy + h / 2)
    W, H = img.size
    if glow:
        g = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(g).text((x, base), text, font=font, anchor="ls", fill=glow, stroke_width=10, stroke_fill=glow)
        img.alpha_composite(g.filter(ImageFilter.GaussianBlur(10)))
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((x + 3, base + 5), text, font=font, anchor="ls", fill=(0, 0, 0, 170), stroke_width=7, stroke_fill=(0, 0, 0, 170))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(3)))
    ImageDraw.Draw(img).text((x, base), text, font=font, anchor="ls", fill=outline + (255,), stroke_width=max(3, size // 16), stroke_fill=outline + (255,))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text((x, base), text, font=font, anchor="ls", fill=255)
    top, bot = base - h, base
    grd = Image.new("RGBA", img.size)
    gd = ImageDraw.Draw(grd)
    for y in range(max(0, top - 4), min(H, bot + 8)):
        t = max(0.0, min(1.0, (y - top) / max(1, h)))
        t2 = t * 2 if t < 0.5 else 1.0
        c = tuple(int(grad[0][i] + (grad[1][i] - grad[0][i]) * (t2 * 0.55 + max(0, t - 0.5) * 0.9)) for i in range(3))
        gd.line([(0, y), (W, y)], fill=c + (255,))
    img.paste(grd, (0, 0), mask)
    # brilho fino no alto das letras
    hi = Image.new("L", img.size, 0)
    ImageDraw.Draw(hi).rectangle([0, top, W, top + max(2, h // 7)], fill=110)
    hi = Image.fromarray(np.minimum(np.asarray(hi), np.asarray(mask)))
    img.paste(Image.new("RGBA", img.size, (255, 255, 255, 255)), (0, 0), hi)

def desk(src, dst, box, cap_h):
    im = Image.open(os.path.join(ROOT, src)).convert("RGBA")
    a = np.array(im)
    m = text_mask(a[..., :3], box)
    bgr = cv2.cvtColor(a[..., :3], cv2.COLOR_RGB2BGR)
    out = cv2.inpaint(bgr, m, 9, cv2.INPAINT_TELEA)
    a[..., :3] = cv2.cvtColor(out, cv2.COLOR_BGR2RGB)
    img = Image.fromarray(a, "RGBA")
    write(img, "EMPATE", (box[0] + box[2]) / 2, (box[1] + box[3]) / 2, cap_h, glow=(160, 190, 255, 70))
    img.save(os.path.join(ROOT, dst), optimize=True)
    print(dst)

# caixas do texto (x0, y0, x1, y1) e altura das maiúsculas, medidas nas artes de derrota
desk("ranked/art/desk_loss_casual.png", "ranked/art/desk_draw_casual.png", (205, 284, 655, 384), 62)
desk("ranked/art/desk_loss_ranked.png", "ranked/art/desk_draw_ranked.png", (205, 284, 655, 384), 62)
desk("ranked/art/desk_bot_loss.png", "ranked/art/desk_bot_draw.png", (288, 150, 662, 236), 58)

# tela cinematográfica: apaga "VITÓRIA!" na arte original (letras douradas), passa o dourado para prata e escreve EMPATE!
v = Image.open(os.path.join(ROOT, "presentation_v019/results/victory.png")).convert("RGBA")
arr = np.array(v)
H, W = arr.shape[:2]
x0, y0, x1, y1 = 196, 206, 700, 334          # letras de VITÓRIA! (medidas na arte 890x660)
sub = arr[y0:y1, x0:x1, :3].astype(int)
r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
letters = ((r > 140) & (r - b > 50)) | ((r + g + b) < 90) & (r > b)
mm = np.zeros((H, W), np.uint8); mm[y0:y1, x0:x1] = (letters * 255).astype(np.uint8)
mm = cv2.dilate(mm, np.ones((9, 9), np.uint8))
mm[:y0 + 4, :] = 0; mm[y1 - 2:, :] = 0
bgr = cv2.cvtColor(arr[..., :3], cv2.COLOR_RGB2BGR)
arr[..., :3] = cv2.cvtColor(cv2.inpaint(bgr, mm, 11, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)
a = arr.astype(np.float32)
rgb = a[..., :3] / 255.0
mx = rgb.max(-1); mn = rgb.min(-1)
sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
gold = (r > b + 0.12) & (sat > 0.25)
lum = 0.3 * r + 0.59 * g + 0.11 * b
steel = np.stack([lum * 0.9, lum * 0.97, np.minimum(1.0, lum * 1.1 + 0.02)], -1) * 0.92
w = np.clip((sat - 0.2) / 0.2, 0, 1) * gold
rgb2 = rgb * (1 - w[..., None]) + steel * w[..., None]
a[..., :3] = np.clip(rgb2 * 255, 0, 255)
img = Image.fromarray(a.astype(np.uint8), "RGBA")
write(img, "EMPATE!", (x0 + x1) / 2, (y0 + y1) / 2 + 2, 70, glow=(150, 185, 255, 70))
img.save(os.path.join(ROOT, "presentation_v019/results/draw.png"), optimize=True)
print("presentation_v019/results/draw.png")
