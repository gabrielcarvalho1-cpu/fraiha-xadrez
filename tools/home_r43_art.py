"""R43 · Home: arte oficial v7 com (1) o casal de volta na ponte e (2) o menu de botões em 92%.
Entrada: tools/home_ref/home_forest_v7_r36_original.png (arte R36 aprovada, intocada)
         ui_v022/assets/home_forest_v6_details.png (casal na ponte, da camada de detalhes antiga)
Saída:   ui_v022/assets/home_forest_v7.png
Menu: bloco dos pilares (530,288)-(1124,918) reduzido a 92% em torno do centro x=827, topo em y=292
(colado no "ESTRATÉGIA PARA IR MAIS LONGE"). O que sobra: colunas vizinhas espelhadas nos lados e o
piso de pedra continuando por baixo. Pontos do menu: x' = 554 + (x-530)*0,92 ; y' = 292 + (y-288)*0,92
(main_hub.gd usa a mesma conta em MENU_ROWS / MENU_X / MENU_W / REF_MENU_RECT)."""
import sys
import numpy as np
from PIL import Image
ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
art = Image.open(ROOT + '/tools/home_ref/home_forest_v7_r36_original.png').convert('RGBA')
det = Image.open(ROOT + '/ui_v022/assets/home_forest_v6_details.png').convert('RGBA')
art.alpha_composite(det.crop((1142, 455, 1223, 526)), (1144, 458))   # casal sobre a mancha da ponte
a = np.asarray(art.convert('RGB')).astype(np.float32)
X0, Y0, X1, Y1, S = 530, 288, 1124, 918, 0.92
menu = Image.fromarray(a[Y0:Y1, X0:X1].astype(np.uint8))
mw, mh = round((X1 - X0) * S), round((Y1 - Y0) * S)
nx0 = round(827 - mw / 2); ny0 = Y0 + 4; nx1 = nx0 + mw; ny1 = ny0 + mh
plate = a.copy()
for x in range(X0, nx0 + 6): plate[Y0:Y1, x] = a[Y0:Y1, 2 * X0 - x - 1]
for x in range(nx1 - 6, X1): plate[Y0:Y1, x] = a[Y0:Y1, 2 * X1 - x - 1]
clean = a[Y1:941, 560:930]                       # piso sem as baquetas
tile = np.concatenate([clean, clean[:, ::-1]], 1)
while tile.shape[1] < X1 - X0: tile = np.concatenate([tile, tile], 1)
FX0, FX1 = 572, 1082
tile = tile[:, :FX1 - FX0]
need = (Y1 - ny1) + 12
seq = []
while len(seq) < need + 4: seq += list(range(clean.shape[0])) + list(range(clean.shape[0] - 1, -1, -1))
wx = np.ones(FX1 - FX0); fe = 12
wx[:fe] = np.linspace(0, 1, fe); wx[-fe:] = np.linspace(1, 0, fe)
for i, y in enumerate(range(Y1 + 3, ny1 - 12, -1)):
    row = tile[seq[i]] * (0.80 + 0.20 * min(1, i / need))
    w = (wx * min(1, i / 3))[:, None]
    plate[y, FX0:FX1] = plate[y, FX0:FX1] * (1 - w) + row * w
img = Image.fromarray(np.clip(plate, 0, 255).astype(np.uint8))
m = menu.resize((mw, mh), Image.LANCZOS)
mk = np.full((mh, mw), 255, np.uint8)
for i in range(6):
    v = int(255 * (i + 1) / 7)
    mk[i, :] = np.minimum(mk[i, :], v); mk[-1 - i, :] = np.minimum(mk[-1 - i, :], v)
    mk[:, i] = np.minimum(mk[:, i], v); mk[:, -1 - i] = np.minimum(mk[:, -1 - i], v)
img.paste(m, (nx0, ny0), Image.fromarray(mk))
img.save(ROOT + '/ui_v022/assets/home_forest_v7.png')
print('ok', (nx0, ny0, mw, mh))
