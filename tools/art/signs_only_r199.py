# R199 · placas JOGUE/APRENDA/EVOLUA/SEMPRE SEM o fundo (recorte automático GrabCut): quando andam para a esquerda
# na Home deitada não levam junto um retângulo de cenário que não combina com o lugar novo.
import cv2, numpy as np
from PIL import Image
X, Y, W, H = 1378, 576, 226, 268
im = np.asarray(Image.open("ui_v022/assets/home_forest_v9.png").convert("RGB"))[Y:Y + H, X:X + W].copy()
bgr = cv2.cvtColor(im, cv2.COLOR_RGB2BGR)
mask = np.zeros(bgr.shape[:2], np.uint8)
bm = np.zeros((1, 65)); fm = np.zeros((1, 65))
cv2.grabCut(bgr, mask, (6, 8, 214, 250), bm, fm, 10, cv2.GC_INIT_WITH_RECT)
m = np.where((mask == 1) | (mask == 3), 255, 0).astype(np.uint8)
n, lab, st, _ = cv2.connectedComponentsWithStats(m)
if n > 1:
    big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    m = np.where(lab == big, 255, 0).astype(np.uint8)
# o poste (embaixo das placas): marrom dentro da faixa do poste
r, g, b = im[..., 0].astype(int), im[..., 1].astype(int), im[..., 2].astype(int)
post = np.zeros_like(m)
post[190:268, 92:140] = np.where((r > g + 15) & (g > b) & (r > 60), 255, 0)[190:268, 92:140]
post = cv2.morphologyEx(post, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
m = np.maximum(m, post)
m = cv2.GaussianBlur(m, (3, 3), 0)
Image.fromarray(np.dstack([im, m]), "RGBA").save("ui_v022/assets/home_wide_signs_only.png", optimize=True)
print("ok")
