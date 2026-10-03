"""R35 · Gera ui_v022/assets/home_forest_v6.png a partir da arte OFICIAL da Home (home_forest_v2.png).

Pedido do dono: o cenário (logo, folhagem, céu, cavalos, chão) NÃO é refeito — só o menu ganha as
linhas novas, sem cortes nem emendas. Por isso:
  • tudo fora da moldura do menu fica com os pixels originais da v2 (logo no tamanho original:
    nada de sombra nem fundo recomposto atrás das letras);
  • a borda de cima (308–334) e a de baixo (852–886) do menu ficam onde estão;
  • só o MIOLO da moldura (x 595–1076, y 334–852 — da borda preta externa até a outra) é
    recomposto com 11 linhas: as 8 originais + 3 novas (moldura do AMIGOS sem ícone/texto);
  • para caber, as linhas perdem só fileiras de pixels REPETIDAS (o verde liso de dentro dos botões
    e os vãos entre eles) — os textos, ícones, molduras e os louros não são esticados nem achatados;
    só o que faltar depois disso é ajustado com uma escala vertical mínima;
  • o fio de luz dos louros do JOGAR RANQUEADO que passa um pouco para fora da moldura acompanha
    a linha (sai da altura antiga e é aplicado na nova).
Imprime MENU_ROWS para ui_v022/main_hub.gd."""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
A = os.path.join(ROOT, "ui_v022/assets")
img = np.array(Image.open(os.path.join(A, "home_forest_v2.png")).convert("RGB")).astype(np.int32)
H, W = img.shape[:2]
X0, X1 = 595, 1077                       # da borda preta externa esquerda até a direita (inclusive)
Y0, Y1 = 334, 852                        # miolo do menu (entre a borda de cima e a de baixo)
B = [334, 397, 456, 533, 595, 657, 721, 785, 852]
FRAMES = [(340, 393), (400, 454), (460, 530), (536, 591), (598, 653), (661, 717), (725, 781), (789, 845)]
bands = [img[B[i]:B[i + 1], X0:X1].copy() for i in range(8)]
# linha nova: moldura do AMIGOS sem ícone e sem texto (cada fileira recebe a cor da coluna limpa)
tpl = bands[4].copy()
fy0, fy1 = 598 - B[4] + 5, 653 - B[4] - 4
for x in range(640 - X0, 965 - X0):
    tpl[fy0:fy1, x] = tpl[fy0:fy1, 980 - X0]
order = [0, 1, 2, 3, "new", "new", 4, 5, 6, "new", 7]
seq = [tpl if o == "new" else bands[o] for o in order]
total = sum(b.shape[0] for b in seq)
target = Y1 - Y0
quota = [b.shape[0] * target / total for b in seq]
hs = [int(np.floor(q)) for q in quota]
for k in np.argsort([-(q - np.floor(q)) for q in quota])[: target - sum(hs)]: hs[k] += 1


CX0, CX1 = 612, 1018                     # conteúdo do botão (ícone + textos); a seta fica na moldura, igual às outras linhas
ANCHOR = 628                             # o conteúdo encolhe por igual a partir daqui (sem achatar)


def uniform(band, h, fr_rel):
    """Moldura: altura ajustada (linhas retas, não se nota). Conteúdo (ícone, textos, seta): encolhe
    por IGUAL na largura e na altura — letras e ícones mantêm a proporção da arte."""
    bh, bw = band.shape[:2]
    s = h / bh
    frame = band.copy()
    f0, f1 = fr_rel[0] + 4, fr_rel[1] - 3
    clean = band[:, 1046 - X0].copy()                        # coluna limpa perto da borda direita
    cl = band.copy()
    for x in range(CX0 - X0, CX1 - X0):
        cl[f0:f1, x] = clean[f0:f1]
    framev = np.array(Image.fromarray(cl.astype(np.uint8)).resize((bw, h), Image.LANCZOS)).astype(np.float64)
    # conteúdo + máscara (o que difere do fundo limpo)
    sub = band[f0:f1, CX0 - X0:CX1 - X0].astype(np.float64)
    bg = cl[f0:f1, CX0 - X0:CX1 - X0].astype(np.float64)
    msk = np.clip((np.abs(sub - bg).sum(axis=2) - 18) / 40.0, 0, 1)
    nw, nh = max(1, int(round(sub.shape[1] * s))), max(1, int(round(sub.shape[0] * s)))
    sub_s = np.array(Image.fromarray(sub.astype(np.uint8)).resize((nw, nh), Image.LANCZOS)).astype(np.float64)
    m_s = np.array(Image.fromarray((msk * 255).astype(np.uint8)).resize((nw, nh), Image.LANCZOS)).astype(np.float64)[..., None] / 255.0
    # a seta fica na ponta direita: o bloco é ancorado à esquerda (ícone/texto) e a seta à direita
    arrow_x = CX1 - CX0
    ox = int(round((ANCHOR - X0) - (ANCHOR - CX0) * s))
    oy = int(round(f0 * s))
    left = sub_s[:, : int(arrow_x * s)]
    ml = m_s[:, : int(arrow_x * s)].copy()
    ml[:, -4:] = 0
    tgt = framev[oy:oy + nh, ox:ox + left.shape[1]]
    framev[oy:oy + nh, ox:ox + left.shape[1]] = left[: tgt.shape[0]] * ml[: tgt.shape[0]] + tgt * (1 - ml[: tgt.shape[0]])
    return np.rint(framev).astype(np.int32)


def carve(band, h):
    """Tira (band_h - h) fileiras repetidas. Fileira repetida = quase igual à de cima. Em cada trecho
    de fileiras repetidas fica pelo menos 1 (o desenho continua igual, só mais baixo)."""
    keep = list(range(band.shape[0]))
    need = band.shape[0] - h
    diff = np.abs(np.diff(band, axis=0)).sum(axis=2)          # (h-1, w)
    e = np.concatenate([[1e9], diff.max(axis=1)])              # pior diferença na fileira inteira
    cand = [y for y in np.argsort(e, kind="stable") if e[y] <= 30]
    removed = set()
    for y in cand:
        if len(removed) >= need: break
        removed.add(int(y))
    keep = [y for y in keep if y not in removed]
    out = band[keep]
    if out.shape[0] != h:                                      # o que faltar: escala vertical mínima
        out = np.array(Image.fromarray(out.astype(np.uint8)).resize((out.shape[1], h), Image.LANCZOS)).astype(np.int32)
    return out, keep, len(removed)


import sys
UNIFORM = "--squash" not in sys.argv
out = img.copy()
y = Y0
rows = []
info = []
for o, b, h in zip(order, seq, hs):
    src_band0 = B[4] if o == "new" else B[o]
    fr0 = FRAMES[4] if o == "new" else FRAMES[o]
    if UNIFORM and o != "new" and o != 2:
        nb = uniform(b, h, (fr0[0] - src_band0, fr0[1] - src_band0))
        keep, nrem = list(range(b.shape[0])), 0
    else:
        nb, keep, nrem = carve(b, h)
    out[y:y + h, X0:X1] = nb
    src_band = B[4] if o == "new" else B[o]
    fr = FRAMES[4] if o == "new" else FRAMES[o]
    # posição da moldura do botão depois do corte (para as áreas de clique)
    k = np.array(keep)
    f0 = int(np.searchsorted(k, fr[0] - src_band))
    f1 = int(np.searchsorted(k, fr[1] - src_band))
    sc = h / len(keep)
    rows.append((round(y + f0 * sc, 1), round((f1 - f0) * sc, 1)))
    info.append((o, b.shape[0], h, nrem, round(sc, 3)))
    if o == 2:
        laurel_dy = (y + (495 - src_band) * 1.0) - 495     # o fio de luz acompanha a linha
        # posição exata: fileira mantida mais próxima de 495 dentro da faixa
        j = int(np.searchsorted(k, 495 - src_band))
        laurel_dy = int(round(y + j * sc)) - 495
    y += h
assert y == Y1

# fio de luz dos louros (fora da moldura): tira da altura antiga e aplica na nova
for xs in [(568, X0), (X1, 1102)]:
    a0, a1 = 492, 499
    seg = img[a0:a1 + 1, xs[0]:xs[1]].astype(np.float64)
    interp = np.array([seg[0] + (seg[-1] - seg[0]) * (i / (a1 - a0)) for i in range(a1 - a0 + 1)])
    glow = np.clip(seg - interp, 0, None)
    out[a0:a1 + 1, xs[0]:xs[1]] = np.rint(interp).astype(np.int32)
    ny = a0 + laurel_dy
    out[ny:ny + glow.shape[0], xs[0]:xs[1]] = np.clip(out[ny:ny + glow.shape[0], xs[0]:xs[1]] + glow, 0, 255).astype(np.int32)

canvas = Image.fromarray(out.astype(np.uint8)).convert("RGBA")
# ícones das linhas novas: a coroa do estandarte (MARCHA REAL) e o verso de carta aprovado (XEQUE)
src = img[396:450, 176:244]
gold = (src[..., 0] > 140) & (src[..., 1] > 95) & (src[..., 2] < 140) & (src[..., 0] > src[..., 2] + 40)
ys_, xs_ = np.nonzero(gold)
crop = src[ys_.min():ys_.max() + 1, xs_.min():xs_.max() + 1]
m = gold[ys_.min():ys_.max() + 1, xs_.min():xs_.max() + 1]
icon = Image.fromarray(np.dstack([crop, m * 255]).astype(np.uint8), "RGBA")
ry, rh = rows[4]
ih = int(round(rh * 0.74))
icon = icon.resize((int(icon.width * ih / icon.height), ih), Image.LANCZOS)
canvas.alpha_composite(icon, (int(665 - icon.width / 2), int(ry + rh / 2 - icon.height / 2)))
back = Image.open(os.path.join(ROOT, "tools/xeque_src/carta_verso.png")).convert("RGBA")
ry, rh = rows[5]
bh = int(round(rh * 0.78))
bw = int(round(bh * back.width / back.height))
card = back.resize((bw, bh), Image.LANCZOS)
fan = Image.new("RGBA", (bw * 2 + 8, bh + 8), (0, 0, 0, 0))
fan.alpha_composite(card.rotate(12, expand=True, resample=Image.BICUBIC).resize((bw + 4, bh + 4)), (0, 2))
fan.alpha_composite(card.rotate(-8, expand=True, resample=Image.BICUBIC).resize((bw + 4, bh + 4)), (bw - 6, 2))
canvas.alpha_composite(fan, (int(665 - fan.width / 2), int(ry + rh / 2 - fan.height / 2)))
canvas.convert("RGB").save(os.path.join(A, "home_forest_v6.png"))

# camada de detalhes vivos: a da v2, sem nada por cima do miolo do menu (o logo é o original)
det = np.array(Image.open(os.path.join(A, "home_forest_v2_details.png")).convert("RGBA"))
det[Y0:Y1, X0:X1, 3] = 0
Image.fromarray(det).save(os.path.join(A, "home_forest_v6_details.png"))

for r in info: print("faixa", r)
print("laurel_dy", laurel_dy)
print("MENU_ROWS =", rows)
