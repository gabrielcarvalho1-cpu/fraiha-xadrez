"""R37 · MARCHA REAL: cartas legíveis + textos do K e do A para as regras novas (pedidos do dono).
  • TODAS as cartas: a caixa colorida de baixo fica maior e o texto (as mesmas palavras) quase dobra
    de tamanho — na mão a carta aparece a ~37% e o texto antigo virava 6 px.
  K  só tira peão da base     → faixa: só o símbolo de SAIR; caixa: "TIRA UM PEÃO / DA BASE"
  A  sai, anda 11 ou anda 1   → faixa: "◆→ ou → 1/11";       caixa: "SAI DA BASE, ANDA / 1 OU 11 CASAS"
Fontes: as da própria carta (Oswald 700 na caixa, serifada Cinzel nos números da faixa), convertidas de
woff para ttf na hora. Originais em tools/marcha_src/ (sem alteração). Saída: marcha/art/cards/."""
import os
import tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "tools/marcha_src")
DST = os.path.join(ROOT, "marcha/art/cards")
tmp = tempfile.mkdtemp()


def ttf(woff, name):
    f = TTFont(os.path.join(ROOT, woff)); f.flavor = None
    p = os.path.join(tmp, name); f.save(p); return p


OSWALD = ttf("marcha/art/fonts/oswald-latin-700-normal.woff", "oswald.ttf")
CINZEL = ttf("account/fonts/Cinzel-Bold.woff", "cinzel.ttf")
CREAM = (241, 227, 189)
GOLD_TOP, GOLD_BOT = (255, 214, 104), (214, 150, 48)
BAND = (136, 421, 380, 486)          # faixa escura de ação (x0, y0, x1, y1)
BOX = (138, 504, 362, 571)           # caixa colorida do texto


def fill_col(a, box, sample_x):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        a[y, x0:x1] = a[y, sample_x]


def fill_rows(a, box, sample_x):
    """Cada fileira recebe a mediana dos pixels ESCUROS dela mesma dentro da faixa/caixa (o degradê
    vertical continua igual; letras e símbolos não entram na conta). sample_x: reserva se não houver."""
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        row = a[y, x0:x1, :3].astype(np.int32)
        lum = row.mean(axis=1)
        ref = np.median(row[lum <= np.percentile(lum, 60)], axis=0) if len(row) else a[y, sample_x, :3]
        a[y, x0:x1, :3] = ref.astype(np.uint8)


def spaced(draw, xy, text, font, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + spacing


def spaced_w(draw, text, font, spacing):
    return sum(draw.textlength(ch, font=font) for ch in text) + spacing * (len(text) - 1)


def box_text(img, lines):
    """Duas linhas centradas na caixa, Oswald com espaçamento como o original (altura das maiúsculas ≈ 17 px)."""
    d = ImageDraw.Draw(img)
    size = 24
    font = ImageFont.truetype(OSWALD, size)
    sp = 1.6
    maxw = BOX[2] - BOX[0] - 22
    while max(spaced_w(d, l, font, sp) for l in lines) > maxw and size > 16:
        size -= 1; font = ImageFont.truetype(OSWALD, size)
    asc = font.getbbox("H")
    cap = asc[3] - asc[1]
    tops = [515, 543]
    for l, top in zip(lines, tops):
        w = spaced_w(d, l, font, sp)
        x = (BOX[0] + BOX[2]) / 2 - w / 2
        spaced(d, (x, top - asc[1] + (17 - cap) / 2), l, font, CREAM, sp)


def gold_text(img, xy, text, size):
    """Número dourado da faixa (degradê vertical, como o "13"/"11" original)."""
    font = ImageFont.truetype(CINZEL, size)
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).text(xy, text, font=font, fill=255)
    a = np.array(img).astype(np.float64)
    mk = np.array(m).astype(np.float64) / 255.0
    ys = np.where(mk.max(axis=1) > 0)[0]
    y0, y1 = ys.min(), ys.max()
    t = np.clip((np.arange(a.shape[0]) - y0) / max(1, y1 - y0), 0, 1)[:, None, None]
    col = np.array(GOLD_TOP) * (1 - t) + np.array(GOLD_BOT) * t
    sh = np.roll(np.roll(mk, 2, axis=0), 2, axis=1)[..., None] * 0.7          # sombra
    a[..., :3] = a[..., :3] * (1 - sh) + np.array([20, 10, 2]) * sh
    a[..., :3] = a[..., :3] * (1 - mk[..., None]) + col * mk[..., None]
    return Image.fromarray(a.astype(np.uint8), img.mode)


def text_w(text, size):
    return ImageDraw.Draw(Image.new("L", (1, 1))).textlength(text, font=ImageFont.truetype(CINZEL, size))


BOX_TEXT = {
    "carta_10_paus": ["ANDA 10 CASAS"], "carta_2_espadas": ["ANDA 2 CASAS"], "carta_3_copas": ["ANDA 3 CASAS"],
    "carta_4_paus": ["SÓ VOLTA 4 CASAS"], "carta_5_ouros": ["QUALQUER PEÇA", "ANDA 5 CASAS"],
    "carta_6_copas": ["ANDA 6 CASAS"], "carta_7_espadas": ["DIVIDE EM DOIS"], "carta_7_paus": ["ATÉ 2 PEÇAS", "DIVIDA AS 7 CASAS"],
    "carta_8_espadas": ["ANDA 8 CASAS"], "carta_9_ouros": ["ANDA 9 CASAS"], "carta_A_copas": ["SAI DA BASE", "OU ANDA 1 OU 11"],
    "carta_J_ouros": ["TROCA DE LUGAR", "COM OUTRA PEÇA"], "carta_K_espadas": ["TIRA UM PEÃO", "DA BASE"],
    "carta_Q_copas": ["ANDA 12 CASAS"],
}
NEW_BOX = (50, 499, 392, 598)        # caixa nova (x0, y0, x1, y1): mais larga e mais alta


def big_box(img, lines):
    a = np.array(img).astype(np.int32)
    # caixa antiga: tudo que não é o creme do fundo entre y 497 e 600, x 100–400
    # só a coluna do meio decide a altura da caixa antiga (assim os índices dos cantos não entram)
    col = a[490:600, 250, :3]
    nc = np.where(np.abs(col - a[490:600, 95, :3]).sum(axis=1) > 40)[0]
    y0, y1 = 490 + nc.min(), 490 + nc.max()
    y0 = max(y0, 497)
    row = a[(y0 + y1) // 2, 100:400, :3]
    ncx = np.where(np.abs(row - a[(y0 + y1) // 2, 95, :3]).sum(axis=1) > 40)[0]
    x0, x1 = 100 + ncx.min(), 100 + ncx.max()
    # cores do degradê da caixa (pixels mais saturados, em cima e embaixo)
    box = a[y0:y1 + 1, x0:x1 + 1, :3]
    sat = box.max(axis=2) - box.min(axis=2)
    lum = box.mean(axis=2)
    fillmask = (sat > 25) & (lum < 150) & (lum > 15)
    rows = np.where(fillmask.any(axis=1))[0]
    r0, r1 = rows[0], rows[-1]
    third = max(2, (r1 - r0) // 3)
    up = box[r0:r0 + third][fillmask[r0:r0 + third]]
    dn = box[r1 - third:r1 + 1][fillmask[r1 - third:r1 + 1]]
    top = np.median(up, axis=0)
    bot = np.median(dn, axis=0)
    # apaga a caixa antiga com o creme da própria fileira
    for y in range(y0 - 1, y1 + 2):
        a[y, x0 - 2:x1 + 3, :3] = a[y, 95, :3]
    # caixa nova: borda escura, filete dourado, degradê do próprio reino da carta
    X0, Y0, X1, Y1 = NEW_BOX
    a[Y0:Y1, X0:X1, :3] = (26, 16, 4)
    a[Y0 + 2:Y1 - 2, X0 + 2:X1 - 2, :3] = (230, 176, 69)
    for y in range(Y0 + 5, Y1 - 5):
        t = (y - Y0 - 5) / float(Y1 - Y0 - 10)
        a[y, X0 + 5:X1 - 5, :3] = (top * (1 - t) + bot * t).astype(np.int32)
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), img.mode)
    d = ImageDraw.Draw(out)
    sp = 2.0
    size = 44 if len(lines) == 1 else 36
    font = ImageFont.truetype(OSWALD, size)
    room = X1 - X0 - 30
    while max(spaced_w(d, l, font, sp) for l in lines) > room and size > 20:
        size -= 1; font = ImageFont.truetype(OSWALD, size)
    hb = font.getbbox("H")
    cap = hb[3] - hb[1]
    gap = 9
    total = cap * len(lines) + gap * (len(lines) - 1)
    y = (Y0 + Y1) / 2 - total / 2
    for l in lines:
        w = spaced_w(d, l, font, sp)
        x = (X0 + X1) / 2 - w / 2
        spaced(d, (x + 2, y - hb[1] + 2), l, font, (10, 4, 0), sp)       # sombra
        spaced(d, (x, y - hb[1]), l, font, (250, 240, 214), sp)
        y += cap + gap
    return out


# ---------------- K: só sai da base
k = Image.open(os.path.join(SRC, "carta_K_espadas.png")).convert("RGBA")
a = np.array(k)
icon = a[426:482, 148:220].copy()                  # símbolo SAIR (losango + seta)
bg = a[426:482, 125:126, :3].astype(np.int32)
diff = np.abs(icon[..., :3].astype(np.int32) - bg).sum(axis=2)
icon[..., 3] = np.clip((diff - 25) * 6, 0, 255).astype(np.uint8)   # só o símbolo (sem o fundo do recorte)
fill_rows(a, BAND, 125)
ic = Image.fromarray(icon).resize((int(72 * 1.25), int(56 * 1.25)), Image.LANCZOS)
k = Image.fromarray(a)
k.alpha_composite(ic, (int(257 - ic.width / 2), int(454 - ic.height / 2)))
k = big_box(k, BOX_TEXT["carta_K_espadas"])
k.save(os.path.join(DST, "carta_K_espadas.png"), optimize=True)

# ---------------- A: sai, anda 11 ou anda 1
ace = Image.open(os.path.join(SRC, "carta_A_copas.png")).convert("RGBA")
a = np.array(ace)
fill_rows(a, (306, 422, 393, 487), 392)            # some o "11" (o símbolo, o "ou" e a seta ficam)
ace = Image.fromarray(a)
size = 40
while text_w("1/11", size) > 76 and size > 26: size -= 1
ace = gold_text(ace, (306, 433 - (size - 40) // 3), "1/11", size)
ace = big_box(ace, BOX_TEXT["carta_A_copas"])
ace.save(os.path.join(DST, "carta_A_copas.png"), optimize=True)

# ---------------- as outras: só a caixa maior
for name, lines in BOX_TEXT.items():
    if name in ("carta_K_espadas", "carta_A_copas"): continue
    im = Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")
    big_box(im, lines).save(os.path.join(DST, name + ".png"), optimize=True)
print("ok")
