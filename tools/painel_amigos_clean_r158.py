#!/usr/bin/env python3
"""R158 · moldura AMIGOS "clean" para o celular: sem a bandeira, o mastro e as varetas soltas da arte original.
Feita só com pedaços da própria arte (parte de baixo espelhada para cima), mesmas cores e cantos."""
import numpy as np
from PIL import Image
src = np.asarray(Image.open('ui_kit/art/painel_amigos.png').convert('RGBA')).copy()
H, W = src.shape[:2]
x0, x1 = 26, 334                      # corta as sobras soltas fora da moldura
bot = src[182:H, x0:x1].copy()        # canto de baixo + borda de baixo (limpos)
bot[..., 3] = np.where(bot[..., 3] < 40, 0, bot[..., 3])
mid_row = src[182:186, x0:x1].copy()  # faixa só com as bordas laterais
top = bot[::-1].copy()
mid = np.repeat(mid_row[1:2], 40, axis=0)
out = np.concatenate([top, mid, bot], axis=0)
out = out[21:out.shape[0] - 21, 3:300].copy()   # sem os pedaços soltos fora da borda
Image.fromarray(out).save('ui_kit/art/painel_amigos_clean.png')
print(out.shape)
