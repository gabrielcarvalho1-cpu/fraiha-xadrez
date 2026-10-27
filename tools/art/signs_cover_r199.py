# R199 · Home deitada no celular: quando as placas JOGUE/APRENDA… andam para a esquerda (tela cortava a arte), as
# placas ORIGINAIS da arte apareciam pela borda (recorte). Esta "capa" é a folhagem da direita da própria arte,
# espelhada e repetida por cima do lugar das placas originais (fica atrás das placas que andaram).
import numpy as np
from PIL import Image
im = np.asarray(Image.open("ui_v022/assets/home_forest_v9.png").convert("RGB")).astype(np.float32)
X0, Y0, X1, Y1 = 1380, 600, 1600, 880          # onde estão as placas originais (e o poste)
src = im[Y0:Y1, 1600:1672]                       # folhagem limpa logo à direita
tile = np.concatenate([src[:, ::-1], src], axis=1)
w = X1 - X0
cov = np.concatenate([tile] * (w // tile.shape[1] + 1), axis=1)[:, :w]
a = np.full(cov.shape[:2], 255.0)
f = 24
for i in range(f):                               # borda esquerda e de cima suaves
    a[:, i] = np.minimum(a[:, i], 255 * (i + 1) / (f + 1))
    a[i, :] = np.minimum(a[i, :], 255 * (i + 1) / (f + 1))
out = np.dstack([cov, a]).astype(np.uint8)
Image.fromarray(out, "RGBA").save("ui_v022/assets/home_wide_signs_cover.png", optimize=True)
print("ok", out.shape)
