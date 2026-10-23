#!/usr/bin/env python3
"""R178d · Home do celular em pé: abre ESPAÇO no meio do menu para o botão do PASSE.
MIOLO (x 138–716): tudo abaixo dos 3 botões grandes (y >= 1110: filete, MARCHA/XEQUE, LIGAS/HISTÓRICO, moldura de
baixo, cena) desce D px; a faixa nova repete o fundo logo abaixo do CONTRA O COMPUTADOR (o botão do PASSE cobre).
LATERAIS (pilares e cena): descem os mesmos D px a partir de y 1000, onde o fuste do pilar é liso (repete um trecho
liso, a tocha não duplica). A cena perde D px no pé (a barra de baixo cobre). A barra (y >= 1655) não muda.
Saída: ui_v022/assets/home_mobile_v9.png
"""
import os
from PIL import Image
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = 96   # R178e · cabe o botão da arte (562x139)
Y_MID, Y_SIDE, NAV = 1110, 930, 1655
X0, X1 = 138, 716
a = np.asarray(Image.open(os.path.join(ROOT, "ui_v022/assets/home_mobile_v8.png")).convert("RGB")).copy()
o = a.copy()
F = 18   # emenda: os últimos F px do trecho repetido se misturam com o que vem depois (sem linha reta)
def shift(x0, x1, y):
    o[y + D:NAV, x0:x1] = a[y:NAV - D, x0:x1]
    o[y:y + D, x0:x1] = a[y:y + D, x0:x1]
    for i in range(F):
        t = (i + 1) / (F + 1)
        yy = y + D - F + i
        o[yy, x0:x1] = (a[yy, x0:x1] * (1 - t) + a[yy - D, x0:x1] * t).astype(np.uint8)
shift(X0, X1, Y_MID)
# miolo do espaço novo: fundo liso do menu (linhas sem filete), embaixo do botão do PASSE
band = a[1148:1156, X0:X1]
o[Y_MID:Y_MID + D, X0:X1] = np.tile(band, (D // band.shape[0] + 1, 1, 1))[:D]
shift(0, X0, Y_SIDE)
shift(X1, 854, Y_SIDE)
Image.fromarray(o).save(os.path.join(ROOT, "ui_v022/assets/home_mobile_v9.png"), optimize=True)
print("ok", o.shape)
