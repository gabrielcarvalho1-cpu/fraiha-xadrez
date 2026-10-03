"""R34 · Gera ui_v022/assets/home_forest_v5.png: a arte oficial da Home (home_forest_v2.png) com o menu
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
# 1) logo: só o TEXTO encolhe (FRAIHA, XADREZ e a placa do subtítulo, mesmos pixels), em volta do
#    topo do texto. Coroa, cavalos, folhagem e céu ficam exatamente como na arte original: nada de
#    recorte retangular nem céu refeito. O fundo verde-escuro atrás das letras antigas é recomposto
#    por inpainting (é um fundo liso), e a parte de baixo fica coberta pelo painel, que sobe.
GROUP = (605, 95, 1055, 310)              # FRAIHA + XADREZ + placa (sem a coroa)
SHAPES = [(615, 95, 1045, 222), (680, 200, 968, 255)]   # letras: só pixels que diferem do fundo
PLAQUE = (610, 255, 1046, 310)            # placa inteira (caixa sólida)
TEXT_SCALE = 0.80
out = img.copy()
gx0, gy0, gx1, gy1 = GROUP
_r = img[95:255, 615:1045].reshape(-1, 3).astype(np.int32)
_dk = _r[(_r.mean(axis=1) < 60) & (_r[:, 1] > _r[:, 0])]
bgc = np.median(_dk, axis=0)                 # verde-escuro do fundo atrás das letras
el = np.zeros(img.shape[:2], np.uint8)
for (x0, y0, x1, y1) in SHAPES:
    reg = img[y0:y1, x0:x1].astype(np.int32)
    d = np.abs(reg - bgc).sum(axis=2)
    lum = reg.mean(axis=2)
    # letras: douradas/marfim ou o contorno escuro colado nelas; folhas (verde-amarelo saturado) ficam de fora
    leafy = (reg[..., 1] > reg[..., 0] + 10) & (reg[..., 1] > 70)
    brown = (reg[..., 0] >= reg[..., 1]) & (lum < 90)          # contorno marrom das letras (o fundo é verde)
    el[y0:y1, x0:x1] = (((d > 120) | brown) & ~leafy).astype(np.uint8) * 255
el = cv2.morphologyEx(el, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
el = cv2.dilate(el, np.ones((3, 3), np.uint8))
px0, py0, px1, py1 = PLAQUE
el[py0:py1, px0:px1] = 255
# o que sai: as letras com uma folga de 4 px (leva junto o brilho dourado em volta) e a placa
rem = cv2.dilate(el, np.ones((9, 9), np.uint8))
# folhas da coroa de folhas encostadas nas letras: ficam com os pixels originais (não são borradas)
_g = img.astype(np.int32)
leaf_px = (_g[..., 1] > _g[..., 0] + 10) & (_g[..., 1] > 70) & (_g[..., 2] < _g[..., 1])
leaf_px = cv2.morphologyEx(leaf_px.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8)) > 0
core = cv2.dilate(el, np.ones((3, 3), np.uint8)) > 0
keep_leaf = leaf_px & ~core
keep_leaf[py0:py1, px0:px1] = False
rem[keep_leaf] = 0
# fundo sem o texto antigo
base = cv2.inpaint(img[:, :, ::-1].astype(np.uint8), rem, 9, cv2.INPAINT_TELEA)[:, :, ::-1]
out = base.astype(img.dtype).copy()
# texto reduzido, colado só onde há texto (máscara reduzida junto), centro x e topo mantidos
cx = (gx0 + gx1) / 2.0
gw, gh = gx1 - gx0, gy1 - gy0
nw, nh = int(round(gw * TEXT_SCALE)), int(round(gh * TEXT_SCALE))
txt = np.array(Image.fromarray(img[gy0:gy1, gx0:gx1].astype(np.uint8)).resize((nw, nh), Image.LANCZOS)).astype(np.float32)
msk = np.array(Image.fromarray(el[gy0:gy1, gx0:gx1]).resize((nw, nh), Image.LANCZOS)).astype(np.float32) / 255.0
msk = cv2.GaussianBlur(msk, (3, 3), 0)[..., None]
nx0 = int(round(cx - nw / 2.0))
dst = out[gy0:gy0 + nh, nx0:nx0 + nw].astype(np.float32)
out[gy0:gy0 + nh, nx0:nx0 + nw] = (txt * msk + dst * (1 - msk)).astype(out.dtype)
lyo, LOGO_SCALE = 0, 1.0                  # (compat.: o logo não muda de lugar)
plaque_bottom = gy0 + int(round((py1 - gy0) * TEXT_SCALE))
# 3) borda de cima do painel logo abaixo do logo; as 11 faixas até o fim original do painel
top = img[TOP[0]:TOP[1], X0:X1]
top_y = plaque_bottom + 2
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
det[gy0:330, gx0:gx1, 3] = 0             # nada de detalhe vivo sobre o texto do logo (ele mudou de tamanho)
Image.fromarray(det).save(os.path.join(ROOT, "ui_v022/assets/home_forest_v5_details.png"))
print("home_forest_v5_details.png")
