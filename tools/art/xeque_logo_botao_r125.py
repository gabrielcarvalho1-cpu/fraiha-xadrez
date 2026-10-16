#!/usr/bin/env python3
"""R125 · XEQUE: logo nova (canto superior esquerdo do PC) e botão XEQUE novo (arte do dono).
- logo: apaga o "RODADA 3 · BLEFE DE CARTAS" da placa (o jogo escreve a rodada certa ao vivo) e recorta.
  Saída xeque/art/interface/logo_r125.png + logo_r125.json (retângulo da placa, em fração da imagem).
- botão: recorta e gera os 5 estados (normal, hover, pressionado, desabilitado, ativado) em 864x520.
Uso: python3 tools/art/xeque_logo_botao_r125.py <logo.png> <botao.png>"""
import sys, os, json
import numpy as np
import cv2
from PIL import Image, ImageEnhance

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "xeque/art/interface")
logo_src, botao_src = sys.argv[1], sys.argv[2]

# ---- logo
im = Image.open(logo_src).convert("RGBA")
a = np.array(im)
x0, y0, x1, y1 = 288, 798, 1162, 864           # texto da placa (arte 1448x1086)
sub = a[y0:y1, x0:x1, :3].astype(int)
lum = sub.mean(-1)
# a placa vira o preto liso dela (com a textura leve de ruído), sem "fantasma" das letras
ref = a[y0 + 4:y1 - 4, x0 - 10:x0 - 2, :3].astype(np.float32)
base = np.median(ref.reshape(-1, 3), axis=0)
rng = np.random.default_rng(7)
for y in range(y0, y1):
    t = (y - y0) / (y1 - y0)
    shade = 1.0 + 0.25 * (0.5 - abs(t - 0.5))
    noise = rng.normal(0, 3.0, (x1 - x0, 1))
    a[y, x0:x1, :3] = np.clip(base * shade + noise, 0, 255).astype(np.uint8)
img = Image.fromarray(a, "RGBA")
bb = img.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox()
img = img.crop(bb)
W, H = img.size
plaque = [(x0 - bb[0]) / W, (y0 - bb[1]) / H, (x1 - x0) / W, (y1 - y0) / H]
img = img.resize((700, round(700 * H / W)), Image.LANCZOS)
img.save(os.path.join(OUT, "logo_r125.png"), optimize=True)
json.dump({"plaque": plaque}, open(os.path.join(OUT, "logo_r125.json"), "w"))
print("logo", img.size, plaque)

# ---- botão
b = Image.open(botao_src).convert("RGBA")
bb = b.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox()
b = b.crop(bb).resize((864, 520), Image.LANCZOS)
def save(im, n): im.save(os.path.join(OUT, "botao_xeque_r125_%s.png" % n), optimize=True)
save(b, "normal")
save(ImageEnhance.Brightness(b).enhance(1.15), "hover")
save(ImageEnhance.Brightness(b).enhance(0.82), "pressionado")
d = ImageEnhance.Brightness(ImageEnhance.Color(b).enhance(0.25)).enhance(0.62)
save(d, "desabilitado")
r = np.array(b).astype(np.float32)
r[..., 0] = np.minimum(255, r[..., 0] * 1.12 + 18); r[..., 1] *= 0.86; r[..., 2] *= 0.82
save(Image.fromarray(r.astype(np.uint8), "RGBA"), "ativado")
print("botao ok")
