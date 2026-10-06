"""R43 · Home em modo janela: laterais completadas (a partir da arte gerada por IA, só as faixas de fora).
Entrada: ui_v022/assets/home_forest_v7.png (arte oficial, já com casal e menu 92%)
         tools/home_ref/home_laterais_ia_r43.png (imagem da IA; só as laterais são usadas)
Saída:   ui_v022/assets/home_forest_v7_wide.png (1840x941 = 84 px de cada lado + 1672 do meio)
O meio é a arte oficial pixel por pixel; só 40 px de cada borda são misturados com a lateral
(e home_forest_v7.png é regravada com essas bordas, sem a sombra escura). Rodar DEPOIS de home_r43_art.py.
Correção pedida pelo dono: a pedra que a IA pôs no canto inferior direito vira folhagem (espelho
da borda original)."""
import sys
import cv2, numpy as np
ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
a = cv2.imread(ROOT + '/ui_v022/assets/home_forest_v7.png').astype(np.float32)
b = cv2.imread(ROOT + '/tools/home_ref/home_laterais_ia_r43.png')
# arte oficial -> imagem da IA (registrado por ORB + RANSAC: escala 0,965, desloc. 78,-10,7)
M = np.array([[0.965329354, -1.52113747e-04, 78.1466436], [1.52113747e-04, 0.965329354, -10.7100981]])
PAD, B = 84, 40   # 40 px: passa da sombra escura que a arte original tem nas bordas (até ~20 px)
Mi = cv2.invertAffineTransform(M); Mi[0, 2] += PAD
W = 1672 + 2 * PAD
w = cv2.warpAffine(b, Mi, (W, 941), flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REFLECT).astype(np.float32)
for y in range(0, 12): w[y] = w[23 - y]            # a IA cortou ~11 px em cima e embaixo
for y in range(929, 941): w[y] = w[2 * 928 - y]
out = w.copy(); out[:, PAD:PAD + 1672] = a
for k in range(B):
    t = k / (B - 1); t = t * t * (3 - 2 * t)   # suave
    xl, xr = PAD + k, PAD + 1671 - k
    out[:, xl] = w[:, xl] * (1 - t) + a[:, k] * t
    out[:, xr] = w[:, xr] * (1 - t) + a[:, 1671 - k] * t
# pedra do canto inferior direito -> folhagem da própria arte, espelhada em torno da coluna 1632
# (antes da sombra da borda); o deslocamento vertical (até 40 px) evita repetir a flor de cima.
S, Y0, Y1, F, DY = PAD + 1672, 766, 892, 14, 40
X0 = S - B
for y in range(Y0, Y1):
    wy = min(1, (y - Y0) / F, (Y1 - 1 - y) / F)
    for x in range(X0, W):
        c = 1632 - (x - X0)
        dy = int(round(DY * min(1.0, (x - X0) / 30.0)))
        out[y, x] = out[y, x] * (1 - wy) + a[min(940, y + dy), c] * wy
out = np.clip(out, 0, 255).astype(np.uint8)
assert np.array_equal(out[:, PAD + B:PAD + 1672 - B], a[:, B:1672 - B].astype(np.uint8)), 'o meio mudou!'
cv2.imwrite(ROOT + '/ui_v022/assets/home_forest_v7_wide.png', out)
# A arte do jogo passa a ser o miolo da larga: as bordas sem a sombra escura, iguais à emenda
# (o jogo desenha a arte por cima da larga; com a sombra aparecia uma linha escura na divisa).
cv2.imwrite(ROOT + '/ui_v022/assets/home_forest_v7.png', out[:, PAD:PAD + 1672])
print('ok', out.shape)
