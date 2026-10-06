"""R44 · moldura do menu fechada embaixo, mochila da esquerda inteira e placa "ESTRATÉGIA" refeita,
a partir da referência do dono (tools/home_ref/home_moldura_ref_r44.png, print de 661x657).
- Registro ORB+RANSAC da referência na arte (escala ~1,139) e nitidez (unsharp) para compensar a ampliação.
- Miolo dos botões continua o NOSSO (textos certos, SAIR centralizado, cliques no lugar).
- Emendas por "costura de menor diferença" (programação dinâmica) entre referência e arte, com 3 px
  de mistura: a divisa passa onde as duas imagens já são parecidas, sem recorte reto.
Ordem: home_r43_art.py → home_r44_frame.py → home_wide_r43.py."""
import sys
import cv2, numpy as np
ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
a = cv2.imread(ROOT + '/ui_v022/assets/home_forest_v7.png').astype(np.float32)
b = cv2.imread(ROOT + '/tools/home_ref/home_moldura_ref_r44.png')
H, W = a.shape[:2]
orb = cv2.ORB_create(6000)
ka, da = orb.detectAndCompute(cv2.cvtColor(a.astype(np.uint8), cv2.COLOR_BGR2GRAY), None)
kb, db = orb.detectAndCompute(cv2.cvtColor(b, cv2.COLOR_BGR2GRAY), None)
m = sorted(cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True).match(db, da), key=lambda x: x.distance)[:800]
pb = np.float32([kb[x.queryIdx].pt for x in m]); pa = np.float32([ka[x.trainIdx].pt for x in m])
M, inl = cv2.estimateAffinePartial2D(pb, pa, ransacReprojThreshold=3)
print('registro', np.round(M, 4).tolist(), int(inl.sum()))
r = cv2.warpAffine(b, M, (W, H), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
blur = cv2.GaussianBlur(r, (0, 0), 1.0)
r = np.clip(r + 0.7 * (r - blur), 0, 255)            # nitidez
diff = np.abs(r - a).sum(2)

def vseam(x0, x1, y0, y1):
    """costura vertical (um x por linha) de menor diferença em [x0,x1) x [y0,y1)"""
    c = diff[y0:y1, x0:x1].copy(); E = c.copy()
    for i in range(1, E.shape[0]):
        p = E[i - 1]; q = np.minimum(p, np.minimum(np.r_[p[1:], 1e9], np.r_[1e9, p[:-1]])); E[i] += q
    xs = np.zeros(y1 - y0, int); xs[-1] = int(np.argmin(E[-1]))
    for i in range(E.shape[0] - 2, -1, -1):
        j = xs[i + 1]; lo = max(0, j - 1); xs[i] = lo + int(np.argmin(E[i, lo:min(E.shape[1], j + 2)]))
    return xs + x0

def hseam(y0, y1, x0, x1):
    global diff
    d0 = diff; diff = diff.T.copy()
    ys = vseam(y0, y1, x0, x1); diff = d0
    return ys

# área da referência: entre as costuras de fora (lados e topo); a base é o fim da arte
L0 = vseam(476, 560, 300, H)                 # lado esquerdo (mochila / plantas)
R0 = vseam(1130, 1215, 300, H)               # lado direito
T0 = hseam(266, 332, 476, 1215)              # topo (acima da placa)
take = np.zeros((H, W), np.float32)
for x in range(476, 1215):
    take[T0[x - 476]:, x] = 1.0
for y in range(300, H):
    take[y, :L0[y - 300]] = 0.0; take[y, R0[y - 300]:] = 0.0
take[:300, :476] = 0; take[:300, 1215:] = 0
for y in range(266, 300):                     # cantos de cima: fecha com as colunas extremas
    take[y, :L0[0]] = 0.0; take[y, R0[0]:] = 0.0
# miolo dos botões: o NOSSO (costuras internas)
IL = vseam(606, 619, 318, 848); IR = vseam(1043, 1053, 318, 848)   # rente às argolas dos botões: os pilares (e tochas) vêm da referência
IT = hseam(306, 326, 640, 1020); IB = hseam(840, 852, 640, 1020)
for y in range(318, 848):
    take[y, IL[y - 318]:IR[y - 318]] = 0.0
for x in range(640, 1020):
    take[IT[x - 640]:318, x] = 0.0
    take[848:IB[x - 640], x] = 0.0
# placa "ESTRATÉGIA PARA IR MAIS LONGE" refeita (sem o sombreado estranho): sempre da referência
PX0, PX1, PY0, PY1 = 636, 1018, 266, 318
pl = np.zeros((H, W), np.float32); pl[PY0:PY1, PX0:PX1] = 1.0
pl = cv2.GaussianBlur(pl, (0, 0), 2.0); pl[PY0 + 4:PY1, PX0 + 4:PX1 - 4] = 1.0
take = np.maximum(take, pl)
take = cv2.GaussianBlur(take, (0, 0), 1.2)    # ~3 px de mistura nas costuras
out = a * (1 - take[..., None]) + r * take[..., None]
# pedras da direita: a referência tinha um bloco encostado no bloco grande da arte ("encavaladas").
# Abaixo de y 770, a partir da base do pilar direito, volta a arte oficial R36 (pedras originais).
orig0 = cv2.imread(ROOT + '/tools/home_ref/home_forest_v7_r36_original.png').astype(np.float32)
SX0, SY0 = 1100, 770
sm = np.zeros((H, W), np.float32); sm[SY0:, SX0:1240] = 1.0
sm = cv2.GaussianBlur(sm, (0, 0), 3.0); sm[:SY0 - 6, :] = 0
out = out * (1 - sm[..., None]) + orig0 * sm[..., None]
# mochila da esquerda INTEIRA (a da arte oficial R36): o recorte vinha do menu encolhido (colunas
# espelhadas) e a referência só mostra metade dela. Couro marrom/laranja da original, contorno suave.
orig = cv2.imread(ROOT + '/tools/home_ref/home_forest_v7_r36_original.png').astype(np.float32)
BX0, BX1, BY0, BY1 = 405, 562, 792, 932
ob = orig[BY0:BY1, BX0:BX1]
bb, gg, rr = ob[..., 0], ob[..., 1], ob[..., 2]
leather = ((rr > gg + 28) & (rr > 70) & (gg < rr * 0.82)).astype(np.uint8)
n, lab, st, _ = cv2.connectedComponentsWithStats(leather)
keep = np.zeros_like(leather)
if n > 1:
    big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    keep = (lab == big).astype(np.uint8)
keep = cv2.morphologyEx(keep, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
cs, _ = cv2.findContours(keep, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
keep = np.zeros_like(keep); cv2.drawContours(keep, cs, -1, 1, thickness=-1)   # fecha buracos (fivela, sombras)
bm = cv2.GaussianBlur(cv2.dilate(keep, np.ones((3, 3), np.uint8)).astype(np.float32), (0, 0), 0.8)
out[BY0:BY1, BX0:BX1] = out[BY0:BY1, BX0:BX1] * (1 - bm[..., None]) + ob * bm[..., None]
cv2.imwrite(ROOT + '/ui_v022/assets/home_forest_v7.png', np.clip(out, 0, 255).astype(np.uint8))
np.save('/tmp/claude-0/frame/take.npy', take)
print('ok')
