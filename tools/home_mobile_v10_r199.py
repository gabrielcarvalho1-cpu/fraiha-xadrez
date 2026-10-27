#!/usr/bin/env python3
"""R199 · Home do celular em pé: a cena CONTINUA para baixo (a v9 perdia 96 px no pé: mochila, baquetas e a metade de
baixo do espírito das águas ficavam cortadas). v10 = v9 (0..1655) + as 96 linhas que a v9 perdeu (v8 1559..1655)
+ a barra de baixo (v9 1655..1842). A barra é posta no fim da tela e passa POR CIMA da cena.
Saída: ui_v022/assets/home_mobile_v10.png (854 x 1938)
"""
import os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = lambda n: np.asarray(Image.open(os.path.join(ROOT, "ui_v022/assets", n)).convert("RGB"))
v8, v9 = A("home_mobile_v8.png"), A("home_mobile_v9.png")
o = np.concatenate([v9[:1655], v8[1559:1655], v9[1655:]], axis=0)
Image.fromarray(o).save(os.path.join(ROOT, "ui_v022/assets/home_mobile_v10.png"), optimize=True)
print("ok", o.shape)
