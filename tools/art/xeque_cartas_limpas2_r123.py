#!/usr/bin/env python3
"""R123.1 · cartas do XEQUE sem NENHUM texto impresso: além do nome/PEÇA/legenda (R55, *_limpa.png), tira
também o número do selo (6 / 2) e o "DE 20". O jogo desenha tudo isso ao vivo, no tamanho exato da tela
(nítido no PC e no celular). Saída: carta_<id>_limpa2.png (720x1008, PC) e carta_<id>_limpa2_cel.png
(360x504, celular — menos memória). Uso: python3 tools/art/xeque_cartas_limpas2_r123.py"""
import os
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
D = os.path.join(ROOT, "xeque/art/cartas")
DIGIT_BOX = (78, 70, 146, 156)     # número escuro dentro do selo bege
DE20_BOX = (598, 70, 660, 136)     # "DE / 20" claro dentro da caixinha preta

def clean(n):
    im = Image.open(os.path.join(D, "carta_%s_limpa.png" % n)).convert("RGBA")
    a = np.array(im)
    rgb = np.ascontiguousarray(a[..., :3])
    lum = rgb.astype(np.float32).mean(axis=2)
    mask = np.zeros(lum.shape, np.uint8)
    x0, y0, x1, y1 = DIGIT_BOX
    mask[y0:y1, x0:x1] = (lum[y0:y1, x0:x1] < 120).astype(np.uint8) * 255
    x0, y0, x1, y1 = DE20_BOX
    mask[y0:y1, x0:x1] = (lum[y0:y1, x0:x1] > 90).astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    out = cv2.inpaint(bgr, mask, 7, cv2.INPAINT_TELEA)
    a[..., :3] = cv2.cvtColor(out, cv2.COLOR_BGR2RGB)
    big = Image.fromarray(a, "RGBA")
    big.save(os.path.join(D, "carta_%s_limpa2.png" % n), optimize=True)
    big.resize((360, 504), Image.LANCZOS).save(os.path.join(D, "carta_%s_limpa2_cel.png" % n), optimize=True)

for n in ["rei", "rainha", "cavalo", "peao"]: clean(n)
print("ok")
