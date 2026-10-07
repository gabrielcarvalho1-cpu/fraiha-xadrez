"""R49 · TABULEIRO RANKED MADEIRA (PC e celular) + SUBIDA DE LIGA = as 3 artes de referência do dono.

Mesma regra da Home (tools/home_ref_v8.py): a referência vira a arte de fundo e só o que é VIVO sai dela, para o
jogo desenhar por cima com os dados reais da partida:
  • tabuleiro: as casas com peças (fileiras 1, 2, 7 e 8) recebem casas LIMPAS da própria arte (mesma coluna, mesma
    cor, 4 fileiras acima/abaixo) — o jogo desenha as peças, destaques e lances por cima, alinhado ao grid;
  • cartões dos jogadores: retrato, nome, liga/PL (e o escudo da liga), dígitos do relógio e o texto "Material"
    (ficam molduras, ampulheta e o peão);
  • PC: texto do estado da voz; título CHAT; textos de SILENCIAR/DENUNCIAR (mudam para REATIVAR/DENUNCIADO);
    "Mensagem…" (o campo escreve o seu); ficam INÍCIO/ESC, ícones da barra, "—" e ENVIAR (fixos);
  • celular: o texto "Na voz" e a bolinha verde (estado real da voz);
  • subida de liga: recorte da moldura com transparência fora dela; saem o nome da liga, "De X para Y", a linha
    do resultado, o "+N PL", "Progresso na Liga …" e "N / 100 PL" (o título, o lema e os botões ficam).
Entradas: tools/board_ref/ranked_madeira_pc_ref.png · ranked_madeira_mobile_ref.png · subida_de_liga_ref.png
Saídas:   ranked/art/board_pc.png · board_mob.png · promo_modal.png
Uso: python3 tools/board_ref_r49.py [raiz_do_repo]"""
import sys, os
import numpy as np
import cv2
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
REF = ROOT + '/tools/board_ref/'
OUT = ROOT + '/ranked/art/'
os.makedirs(OUT, exist_ok=True)


def load(p):
    return np.array(Image.open(p).convert('RGB'))


def rect_mask(shape, box):
    m = np.zeros(shape[:2], np.uint8)
    cv2.rectangle(m, (int(box[0]), int(box[1])), (int(box[2]), int(box[3])), 255, -1)
    return m


def circle_mask(shape, c, r):
    m = np.zeros(shape[:2], np.uint8)
    cv2.circle(m, (int(c[0]), int(c[1])), int(r), 255, -1)
    return m


def fill_dark(img, mask, sigma=14, known_max=62, seed=49):
    """Recompõe o fundo ESCURO sob a máscara: média gaussiana só dos pixels escuros em volta, + grão fino."""
    f = img.astype(np.float64)
    lum = f.mean(axis=2)
    known = ((mask == 0) & (lum < known_max)).astype(np.float64)
    num = np.stack([cv2.GaussianBlur(f[..., c] * known, (0, 0), sigma) for c in range(3)], axis=2)
    den = cv2.GaussianBlur(known, (0, 0), sigma)[..., None] + 1e-6
    rng = np.random.default_rng(seed)
    filled = np.clip(num / den + rng.normal(0, 1.4, f.shape[:2])[..., None], 0, 255)
    a = cv2.GaussianBlur((mask > 0).astype(np.float64), (0, 0), 1.0)
    a = np.where(mask > 0, 1.0, a)[..., None]
    return (f * (1 - a) + filled * a).astype(np.uint8)


def erase_text(img, boxes, thr=22, grow=2, blur=21):
    """Texto claro sobre fundo escuro/médio: some por inpaint (como home_r441_text.py), só dentro das caixas."""
    bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    lum = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
    bgl = cv2.cvtColor(cv2.medianBlur(bgr, blur), cv2.COLOR_BGR2GRAY).astype(np.float32)
    mask = np.zeros(lum.shape, np.uint8)
    clip = np.zeros_like(mask)
    for (x0, y0, x1, y1) in boxes:
        mask[y0:y1, x0:x1] = ((lum[y0:y1, x0:x1] - bgl[y0:y1, x0:x1]) > thr).astype(np.uint8)
        clip[y0:y1, x0:x1] = 1
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=grow) & clip
    out = cv2.inpaint(bgr, mask * 255, 5, cv2.INPAINT_TELEA)
    soft = cv2.GaussianBlur(out, (0, 0), 1.6)
    mf = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 1.5)[..., None]
    out = (out * (1 - mf) + soft * mf).astype(np.uint8)
    return cv2.cvtColor(out, cv2.COLOR_BGR2RGB)


def edges(a, b):
    return [int(round(a + (b - a) * i / 8.0)) for i in range(9)]


def regrid(img, xs, ys):
    """A arte gerada não tem as casas todas iguais (a 1ª/última fileira é um pouco maior). Cada casa da arte
    (bordas MEDIDAS xs/ys) é redimensionada para a sua casa num grid UNIFORME com as mesmas bordas externas —
    assim o grid do jogo (casas iguais) cai exatamente sobre as casas desenhadas."""
    out = img.copy()
    ux, uy = edges(xs[0], xs[8]), edges(ys[0], ys[8])
    for r in range(8):
        for c in range(8):
            sx0, sx1, sy0, sy1 = int(round(xs[c])), int(round(xs[c + 1])), int(round(ys[r])), int(round(ys[r + 1]))
            cell = img[sy0:sy1, sx0:sx1]
            out[uy[r]:uy[r + 1], ux[c]:ux[c + 1]] = cv2.resize(cell, (ux[c + 1] - ux[c], uy[r + 1] - uy[r]), interpolation=cv2.INTER_AREA)
    return out


def clean_board(img, xs, ys):
    """Casas das fileiras 0,1,6,7 (com peças) ← casa limpa da mesma coluna 4 fileiras adiante (mesma cor)."""
    img = regrid(img, xs, ys)
    out = img.copy()
    ux, uy = edges(xs[0], xs[8]), edges(ys[0], ys[8])
    for r in (0, 1, 6, 7):
        s = r + 4 if r < 2 else r - 4
        for c in range(8):
            cell = img[uy[s]:uy[s + 1], ux[c]:ux[c + 1]]
            out[uy[r]:uy[r + 1], ux[c]:ux[c + 1]] = cv2.resize(cell, (ux[c + 1] - ux[c], uy[r + 1] - uy[r]), interpolation=cv2.INTER_AREA)
    return out


# ================================ PC (1672 x 941) ================================
pc = load(REF + 'ranked_madeira_pc_ref.png')
assert pc.shape == (941, 1672, 3), pc.shape
# bordas das casas MEDIDAS na referência (transições claro/escuro)
PC_XS = [382.0, 470.0, 557.0, 642.0, 727.0, 813.0, 899.0, 985.0, 1075.5]
PC_YS = [145.5, 235.0, 321.0, 408.0, 493.0, 580.0, 665.0, 751.0, 839.5]
o = clean_board(pc, PC_XS, PC_YS)
# barra de cima: estado da voz (os ícones ficam)
o = fill_dark(o, rect_mask(o.shape, (1246, 27, 1408, 64)), 10)
# cartões (adversário em cima; VOCÊ = +566 px)
for dy in (0, 566):
    o = fill_dark(o, circle_mask(o.shape, (1219, 180 + dy), 41), 16)             # retrato
    o = fill_dark(o, rect_mask(o.shape, (1277, 146 + dy, 1462, 180 + dy)))         # nome
    o = fill_dark(o, rect_mask(o.shape, (1276, 189 + dy, 1462, 221 + dy)))         # escudo + liga/PL
    o = fill_dark(o, rect_mask(o.shape, (1523, 154 + dy, 1632, 202 + dy)))         # dígitos do relógio
    o = fill_dark(o, rect_mask(o.shape, (1244, 246 + dy, 1365, 274 + dy)))         # "Material: N"
# chat: título, SILENCIAR/DENUNCIAR (texto muda), placeholder
o = fill_dark(o, rect_mask(o.shape, (1188, 326, 1274, 358)))
o = erase_text(o, [(1322, 328, 1422, 352), (1450, 328, 1561, 352)], thr=30)
o = fill_dark(o, rect_mask(o.shape, (1190, 618, 1385, 650)), 10)
Image.fromarray(o).save(OUT + 'board_pc.png', optimize=True)

# ============================= CELULAR (888 x 1772) =============================
mb = load(REF + 'ranked_madeira_mobile_ref.png')
assert mb.shape == (1772, 888, 3), mb.shape
MB_XS = [53.2, 151.0, 250.0, 347.0, 444.0, 542.0, 638.0, 737.0, 835.0]
MB_YS = [461.0, 568.0, 666.0, 764.0, 862.0, 960.0, 1058.0, 1156.0, 1260.0]
m = clean_board(mb, MB_XS, MB_YS)
for dy in (0, 1042):
    m = fill_dark(m, circle_mask(m.shape, (90, 340 + dy), 45), 16)
    m = fill_dark(m, rect_mask(m.shape, (158, 292 + dy, 380, 334 + dy)))
    m = fill_dark(m, rect_mask(m.shape, (156, 337 + dy, 382, 386 + dy)))
    m = fill_dark(m, rect_mask(m.shape, (494, 333 + dy, 614, 368 + dy)))
    m = fill_dark(m, rect_mask(m.shape, (718, 308 + dy, 850, 370 + dy)))
# voz: bolinha verde e "Na voz"
m = fill_dark(m, rect_mask(m.shape, (462, 1584, 600, 1632)), 10)
Image.fromarray(m).save(OUT + 'board_mob.png', optimize=True)

# ======================== SUBIDA DE LIGA (recorte com alfa) ========================
pr = load(REF + 'subida_de_liga_ref.png')
X0, Y0, X1, Y1 = 430, 14, 1242, 920
p = pr.copy()
p = fill_dark(p, rect_mask(p.shape, (712, 494, 960, 551)), 16, known_max=70)          # nome da liga (FERRO)
p = fill_dark(p, rect_mask(p.shape, (690, 552, 984, 580)), 12, known_max=70)          # De Madeira para Ferro
p = fill_dark(p, rect_mask(p.shape, (560, 643, 950, 678)), 10)                        # Vitória · Relâmpago · Desistência
p = fill_dark(p, rect_mask(p.shape, (982, 644, 1104, 680)), 8, known_max=80)          # +3 PL (a moldura do selo fica)
p = fill_dark(p, rect_mask(p.shape, (560, 703, 770, 727)), 10)                        # Progresso na Liga Ferro
p = fill_dark(p, rect_mask(p.shape, (1005, 703, 1110, 727)), 10)                      # 0 / 100 PL
crop = p[Y0:Y1, X0:X1].astype(np.float64)
lum = crop.mean(axis=2)
alpha = np.zeros(lum.shape)
# corpo da moldura (retângulo verde + bordas douradas): opaco
alpha[95 - Y0 + Y0:, :] = 0
alpha[110 - Y0:905 - Y0, 470 - X0:1200 - X0] = 1.0
# fora do corpo: só o que é ornamento (cavalos, coroa, estandartes, folhas e brilhos claros) fica
orn = np.clip((lum - 48.0) / 30.0, 0, 1)
orn = cv2.dilate(orn, np.ones((5, 5), np.uint8))
alpha = np.maximum(alpha, orn)
alpha = cv2.GaussianBlur(alpha, (0, 0), 1.6)
alpha[110 - Y0:905 - Y0, 470 - X0:1200 - X0] = 1.0
rgba = np.dstack([crop, alpha * 255]).astype(np.uint8)
Image.fromarray(rgba, 'RGBA').save(OUT + 'promo_modal.png', optimize=True)
print('ok')
