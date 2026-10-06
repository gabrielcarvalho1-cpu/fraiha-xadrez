"""R44.1 · tira da arte os textos das 11 linhas do menu (ficavam serrilhados depois de reduzir a
arte); o jogo escreve por cima com a fonte do jogo (main_hub.gd · RefCaption), nítida em qualquer tela.
Fica na arte: moldura das linhas, ícones, setas e os selos NOVO. Rodar depois de home_r44_frame.py
e antes de home_wide_r43.py."""
import sys
import cv2, numpy as np
ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
p = ROOT + '/ui_v022/assets/home_forest_v7.png'
a = cv2.imread(p)
ROWS = [(325.1, 42.8), (372.0, 42.8), (420.3, 50.6), (478.8, 42.8), (524.8, 42.8), (571.7, 42.3), (617.7, 42.8),
        (663.7, 42.8), (710.6, 41.9), (756.6, 41.9), (801.7, 41.9)]
lum = cv2.cvtColor(a, cv2.COLOR_BGR2GRAY).astype(np.float32)
bg = cv2.medianBlur(a, 21)
bgl = cv2.cvtColor(bg, cv2.COLOR_BGR2GRAY).astype(np.float32)
mask = np.zeros(lum.shape, np.uint8)
for i, (y, h) in enumerate(ROWS):
    y0, y1 = int(y + 5), int(y + h - 4)
    x0 = 716 if i == 2 else 702
    x1 = 895 if i in (4, 5) else (988 if i == 2 else 978)
    m = ((lum[y0:y1, x0:x1] - bgl[y0:y1, x0:x1]) > 22).astype(np.uint8)
    mask[y0:y1, x0:x1] = m
mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=2)
out = cv2.inpaint(a, mask, 4, cv2.INPAINT_TELEA)
# suaviza só onde havia texto (sem manchas)
soft = cv2.GaussianBlur(out, (0, 0), 1.6)
mf = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 1.5)[..., None]
out = (out * (1 - mf) + soft * mf).astype(np.uint8)
cv2.imwrite(p, out)
print('ok', int(mask.sum()))
