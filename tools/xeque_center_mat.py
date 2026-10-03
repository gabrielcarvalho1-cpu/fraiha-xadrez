"""R37.2 · XEQUE: o círculo (tapete com a coroa) volta ao CENTRO do tabuleiro xadrez da arte.
Na arte aprovada ele estava 44 px abaixo do centro (centro do xadrez: x 836, y 498; tapete: y 542).
  • as casas de xadrez debaixo do tapete antigo são refeitas com as próprias casas da arte, copiadas
    de 2 casas ao lado (o xadrez repete a cada 131 px na horizontal e 113 px na vertical — mesma cor);
  • o tapete (xeque/art/mesa/tapete.png, igual ao da arte) é colado de novo, centrado, com a mesma sombra.
Entrada: tools/xeque_src/mesa_cena_com_tapete_original.png (sem alteração). Saída: xeque/art/mesa/mesa_cena_com_tapete.png
Depois rode tools/xeque_scene_soft.py (versões esfumada e desfocada)."""
import os
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "tools/xeque_src/mesa_cena_com_tapete_original.png")
DST = os.path.join(ROOT, "xeque/art/mesa/mesa_cena_com_tapete.png")
TAP = os.path.join(ROOT, "xeque/art/mesa/tapete.png")
OLD = (715, 421)                     # canto do tapete na arte original (achado por correspondência exata)
CENTER = (836, 498)                  # centro do xadrez
BOARD = (583, 274, 1092, 724)        # casas do xadrez (x0, y0, x1, y1)
PX, PY = 131, 113                    # período do xadrez (2 casas)

sc = np.array(Image.open(SRC).convert("RGB")).astype(np.float64)
tap = np.array(Image.open(TAP).convert("RGBA")).astype(np.float64)
th, tw = tap.shape[:2]
H, W = sc.shape[:2]
# máscara do tapete antigo + sombra em volta (12 px)
m = np.zeros((H, W), np.uint8)
m[OLD[1]:OLD[1] + th, OLD[0]:OLD[0] + tw] = (tap[..., 3] > 8).astype(np.uint8)
m = cv2.dilate(m, np.ones((31, 31), np.uint8))
out = sc.copy()
ys, xs = np.where(m > 0)
cands = sorted([(k * PX, j * PY) for k in range(-4, 5) for j in range(-4, 5) if (k, j) != (0, 0)], key=lambda d: d[0] ** 2 + d[1] ** 2)
for y, x in zip(ys, xs):
    if not (BOARD[0] <= x <= BOARD[2] and BOARD[1] <= y <= BOARD[3]): continue
    for dx, dy in cands:
        sx, sy = x + dx, y + dy
        if BOARD[0] + 2 <= sx <= BOARD[2] - 2 and BOARD[1] + 2 <= sy <= BOARD[3] - 2 and m[sy, sx] == 0:
            out[y, x] = sc[sy, sx]
            break
dx, dy = CENTER[0] - (OLD[0] + tw / 2), CENTER[1] - (OLD[1] + th / 2)
# sombra suave do tapete (como a da arte): alfa desfocado, um pouco para baixo
nx0, ny0 = int(round(OLD[0] + dx)), int(round(OLD[1] + dy))
al = np.zeros((H, W))
al[ny0 + 6:ny0 + 6 + th, nx0:nx0 + tw] = tap[..., 3] / 255.0
shadow = cv2.GaussianBlur(al, (0, 0), 7) * 0.45
out = out * (1 - shadow[..., None])
# tapete centrado
nx, ny = int(round(OLD[0] + dx)), int(round(OLD[1] + dy))
a = tap[..., 3:4] / 255.0
out[ny:ny + th, nx:nx + tw] = out[ny:ny + th, nx:nx + tw] * (1 - a) + tap[..., :3] * a
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(DST)
print("ok", (nx, ny), "deslocamento", dx, dy)
