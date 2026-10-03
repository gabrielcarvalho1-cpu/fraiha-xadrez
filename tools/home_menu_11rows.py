"""R33.1 · Gera ui_v022/assets/home_forest_v5.png: a arte oficial da Home (home_forest_v2.png) com o menu
recomposto em 11 linhas — as 8 linhas originais (mesmos pixels, só compactadas na vertical) + 3 linhas
novas feitas da moldura da própria arte (MARCHA REAL e XEQUE depois de LIGAS E RANKING;
HISTÓRICO DE PARTIDAS depois de CONHEÇA O FRAIHA). Textos e ícones das linhas novas são desenhados
pelo jogo por cima (o ícone do XEQUE é o verso de carta aprovado do modo).
Imprime as posições usadas em main_hub.gd (MENU_ROWS). Substitui tools/home_menu_10rows.py."""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "ui_v022/assets/home_forest_v2.png")
OUT = os.path.join(ROOT, "ui_v022/assets/home_forest_v5.png")
# R33.1: logo menor (o painel sobe) e o chão de pedra embaixo do painel volta a aparecer, como na v2
LOGO = (440, 0, 1240, 308)              # logo inteiro: coroa, FRAIHA XADREZ, cavalos e a faixa do subtítulo
LOGO_SCALE = 0.82
TOP = (308, 334)                        # borda de cima do painel (linha dourada com losango)
PANEL_END = 886                         # fim do painel na arte original (o chão começa aqui)
X0, X1 = 586, 1090                      # colunas do painel (bordas + louros)
B = [334, 397, 456, 533, 595, 657, 721, 785, 852]   # limites das 8 faixas (no meio dos vãos)
FRAMES = [(340, 393), (400, 454), (460, 530), (536, 591), (598, 653), (661, 717), (725, 781), (789, 845)]
BOTTOM = (852, 886)                     # vão final + borda inferior + losango
img = np.array(Image.open(SRC).convert("RGB"))
bands = [img[B[i]:B[i + 1], X0:X1].copy() for i in range(8)]
# faixa nova: moldura do AMIGOS sem ícone e sem texto (preenche com a coluna limpa da própria linha)
tpl = bands[4].copy()
fy0, fy1 = 598 - B[4] + 5, 653 - B[4] - 4
clean_x = 980 - X0
for x in range(640 - X0, 965 - X0):
    tpl[fy0:fy1, x] = tpl[fy0:fy1, clean_x]
order = [0, 1, 2, 3, "new", "new", 4, 5, 6, "new", 7]
seq = [tpl if o == "new" else bands[o] for o in order]
total = sum(b.shape[0] for b in seq)
bottom = img[BOTTOM[0]:BOTTOM[1], X0:X1]
import cv2
# 1) logo reduzido (mesmos pixels): recorta o logo COM a folhagem e o fundo em volta, reduz em torno
#    do centro do logo e funde as bordas do recorte na arte original. O recorte é mais largo que o
#    logo, então o próprio recorte reduzido cobre os cavalos originais; à direita ele para antes da
#    placa do perfil, e o pedaço do cavalo branco que sobra sobre o céu é preenchido pelo próprio céu.
lx0, ly0, lx1, ly1 = LOGO
CROP = (371, 0, 1215, 360)
CX = (lx0 + lx1) / 2.0
out = img.copy()
cw_, ch_ = CROP[2] - CROP[0], CROP[3] - CROP[1]
lw, lh = int(round(cw_ * LOGO_SCALE)), int(round(ch_ * LOGO_SCALE))
logo = np.array(Image.fromarray(img[CROP[1]:CROP[3], CROP[0]:CROP[2]].astype(np.uint8)).resize((lw, lh), Image.LANCZOS)).astype(np.float32)
lxo = int(round(CX - (CX - CROP[0]) * LOGO_SCALE))
lyo = 4
# sobra do cavalo branco (fora do recorte reduzido, sobre o céu): céu do pôr do sol reconstruído
# linha a linha com a cor da faixa de céu logo à direita do louro (x 1194–1214, antes da placa do
# perfil), com o leve ruído de pixel da própria faixa; acima das orelhas fica a copa original.
R0, R1 = lxo + lw - 34, 1200
Y0, Y1 = 54, 318
rng_ = np.random.default_rng(7)
for y in range(Y0, Y1):
    strip = img[y, 1200:1216].astype(np.float32)
    med = np.median(strip, axis=0)
    noise = rng_.integers(0, strip.shape[0], R1 - R0)
    row = 0.75 * med + 0.25 * strip[noise]
    # funde com a arte original na borda de cima, na de baixo e à direita
    t = min(1.0, (y - Y0) / 14.0) * min(1.0, (Y1 - y) / 18.0)
    xs_ = np.arange(R0, R1)
    w = np.clip((R1 - xs_) / 4.0, 0, 1) * np.clip((xs_ - R0) / 14.0, 0, 1) * t
    out[y, R0:R1] = (row * w[:, None] + img[y, R0:R1].astype(np.float32) * (1 - w[:, None])).astype(out.dtype)
yy, xx = np.mgrid[0:lh, 0:lw]
feather = 24.0
alpha = np.clip(np.minimum(np.minimum(xx / feather, (lw - 1 - xx) / feather), (lh - 1 - yy) / feather), 0, 1)
# a lanterna da esquerda (x < 432, y > 165 na arte original) não entra no recorte reduzido: fica a original
srcx = CROP[0] + xx / LOGO_SCALE
srcy = CROP[1] + yy / LOGO_SCALE
lantern = np.clip((432 - srcx) / 14.0, 0, 1) * np.clip((srcy - 150) / 14.0, 0, 1)
alpha = (alpha * (1 - lantern))[..., None]
dst = out[lyo:lyo + lh, lxo:lxo + lw].astype(np.float32)
out[lyo:lyo + lh, lxo:lxo + lw] = (logo * alpha + dst * (1 - alpha)).astype(out.dtype)
# 3) borda de cima do painel logo abaixo do logo; as 11 faixas até o fim original do painel
top = img[TOP[0]:TOP[1], X0:X1]
top_y = lyo + int(round(TOP[0] * LOGO_SCALE)) + 1
out[top_y:top_y + top.shape[0], X0:X1] = top
start = top_y + top.shape[0]
end_y = PANEL_END - bottom.shape[0]
scale = (end_y - start) / total
y = float(start)
rows = []
for o, b in zip(order, seq):
    h = b.shape[0] * scale
    y0, y1 = int(round(y)), int(round(y + h))
    piece = Image.fromarray(b).resize((X1 - X0, y1 - y0), Image.LANCZOS)
    out[y0:y1, X0:X1] = np.array(piece)
    # moldura do botão dentro da faixa (para as áreas de clique)
    src_frame = FRAMES[4] if o == "new" else FRAMES[o]
    src_band = B[4] if o == "new" else B[o]
    rows.append((round(y + (src_frame[0] - src_band) * scale, 1), round((src_frame[1] - src_frame[0]) * scale, 1)))
    y += h
by = int(round(y))
out[by:by + bottom.shape[0], X0:X1] = bottom
Image.fromarray(out.astype(np.uint8)).save(OUT)
print("scale", round(scale, 4), "bottom", by)
print("MENU_ROWS =", rows)

# ícone da MARCHA REAL: a coroa dourada do estandarte da própria arte (pixels dourados, fundo removido)
src = img[396:450, 176:244].astype(int)
gold = (src[..., 0] > 140) & (src[..., 1] > 95) & (src[..., 2] < 140) & (src[..., 0] > src[..., 2] + 40)
ys, xs = np.nonzero(gold)
crop = src[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
m = gold[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
rgba = np.dstack([crop, (m * 255)]).astype(np.uint8)
icon = Image.fromarray(rgba, "RGBA")
iw = 50
icon = icon.resize((iw, int(icon.height * iw / icon.width)), Image.NEAREST)
row_y, row_h = rows[4]
cx, cy = 665, row_y + row_h / 2.0
base = Image.fromarray(out)
base.alpha_composite = None
canvas = base.convert("RGBA")
canvas.alpha_composite(icon, (int(cx - icon.width / 2), int(cy - icon.height / 2)))
# ícone do XEQUE: o verso de carta aprovado (tools/xeque_src/carta_verso.png), pequeno e inclinado
back = Image.open(os.path.join(ROOT, "tools/xeque_src/carta_verso.png")).convert("RGBA")
bh = int(round(rows[5][1] * 0.78))
bw = int(round(bh * back.width / back.height))
card = back.resize((bw, bh), Image.LANCZOS)
fan = Image.new("RGBA", (bw * 2 + 8, bh + 8), (0, 0, 0, 0))
fan.alpha_composite(card.rotate(12, expand=True, resample=Image.BICUBIC).resize((bw + 4, bh + 4)), (0, 2))
fan.alpha_composite(card.rotate(-8, expand=True, resample=Image.BICUBIC).resize((bw + 4, bh + 4)), (bw - 6, 2))
row_y5, row_h5 = rows[5]
canvas.alpha_composite(fan, (int(665 - fan.width / 2), int(row_y5 + row_h5 / 2 - fan.height / 2)))
xeque_icon = fan
canvas.convert("RGB").save(OUT)
print("coroa colada em", cx, round(cy, 1))

# linhas novas para o menu do CELULAR (mesmo recorte 444x60 das outras linhas, sem escala)
row = img[596:656, 615:1059].copy()
for x in range(640 - 615, 965 - 615):
    row[7:52, x] = row[7:52, 980 - 615]
Image.fromarray(row).save(os.path.join(ROOT, "ui_v022/assets/home_row_blank.png"))
r2 = Image.fromarray(row).convert("RGBA")
ic2 = Image.fromarray(rgba, "RGBA").resize((54, int(Image.fromarray(rgba, "RGBA").height * 54 / Image.fromarray(rgba, "RGBA").width)), Image.NEAREST)
r2.alpha_composite(ic2, (int(665 - 615 - ic2.width / 2), int(30 - ic2.height / 2)))
r2.convert("RGB").save(os.path.join(ROOT, "ui_v022/assets/home_row_marcha.png"))
r3 = Image.fromarray(row).convert("RGBA")
fi = xeque_icon.resize((int(xeque_icon.width * 46 / xeque_icon.height), 46), Image.LANCZOS)
r3.alpha_composite(fi, (int(665 - 615 - fi.width / 2), int(30 - fi.height / 2)))
r3.convert("RGB").save(os.path.join(ROOT, "ui_v022/assets/home_row_xeque.png"))
print("linhas do celular: home_row_blank.png, home_row_marcha.png, home_row_xeque.png")

# camada de detalhes vivos (gato, viajantes…): nada por cima do painel novo, que agora desce até o rodapé
det = np.array(Image.open(os.path.join(ROOT, "ui_v022/assets/home_forest_v2_details.png")).convert("RGBA"))
det[top_y:941, X0:X1, 3] = 0
det[0:330, lx0:lx1, 3] = 0              # nada de detalhe vivo sobre o logo (ele mudou de tamanho)
Image.fromarray(det).save(os.path.join(ROOT, "ui_v022/assets/home_forest_v5_details.png"))
print("home_forest_v5_details.png")
