"""R33 · Gera ui_v022/assets/home_forest_v4.png: a arte oficial da Home (home_forest_v2.png) com o menu
recomposto em 11 linhas — as 8 linhas originais (mesmos pixels, só compactadas na vertical) + 3 linhas
novas feitas da moldura da própria arte (MARCHA REAL e BLEFE REAL depois de LIGAS E RANKING;
HISTÓRICO DE PARTIDAS depois de CONHEÇA O FRAIHA). Textos e ícones das linhas novas são desenhados
pelo jogo por cima (o ícone do BLEFE REAL é o verso de carta aprovado do modo).
Imprime as posições usadas em main_hub.gd (MENU_ROWS). Substitui tools/home_menu_10rows.py."""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "ui_v022/assets/home_forest_v2.png")
OUT = os.path.join(ROOT, "ui_v022/assets/home_forest_v4.png")
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
end_y = 941 - bottom.shape[0] - 1
scale = (end_y - B[0]) / total
out = img.copy()
y = float(B[0])
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
Image.fromarray(out).save(OUT)
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
# ícone do BLEFE REAL: o verso de carta aprovado (tools/blefe_src/carta_verso.png), pequeno e inclinado
back = Image.open(os.path.join(ROOT, "tools/blefe_src/carta_verso.png")).convert("RGBA")
bh = int(round(rows[5][1] * 0.78))
bw = int(round(bh * back.width / back.height))
card = back.resize((bw, bh), Image.LANCZOS)
fan = Image.new("RGBA", (bw * 2 + 8, bh + 8), (0, 0, 0, 0))
fan.alpha_composite(card.rotate(12, expand=True, resample=Image.BICUBIC).resize((bw + 4, bh + 4)), (0, 2))
fan.alpha_composite(card.rotate(-8, expand=True, resample=Image.BICUBIC).resize((bw + 4, bh + 4)), (bw - 6, 2))
row_y5, row_h5 = rows[5]
canvas.alpha_composite(fan, (int(665 - fan.width / 2), int(row_y5 + row_h5 / 2 - fan.height / 2)))
blefe_icon = fan
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
fi = blefe_icon.resize((int(blefe_icon.width * 46 / blefe_icon.height), 46), Image.LANCZOS)
r3.alpha_composite(fi, (int(665 - 615 - fi.width / 2), int(30 - fi.height / 2)))
r3.convert("RGB").save(os.path.join(ROOT, "ui_v022/assets/home_row_blefe.png"))
print("linhas do celular: home_row_blank.png, home_row_marcha.png, home_row_blefe.png")

# camada de detalhes vivos (gato, viajantes…): nada por cima do painel novo, que agora desce até o rodapé
det = np.array(Image.open(os.path.join(ROOT, "ui_v022/assets/home_forest_v2_details.png")).convert("RGBA"))
det[B[0]:941, X0:X1, 3] = 0
Image.fromarray(det).save(os.path.join(ROOT, "ui_v022/assets/home_forest_v3_details.png"))
print("home_forest_v3_details.png (o mesmo da v3: a área do painel já está limpa)")
