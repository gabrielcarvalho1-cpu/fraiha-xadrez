"""R37.2 · XEQUE: faixa de baixo das cartas legível na mão (pedido do dono: "não dá pra ler").
Na mão a carta aparece com ~150 px de largura; a palavra (PEÇA / CORINGA) e a linha pequena
("Pode ser a peça pedida") viravam 4–6 px. Aqui a faixa escura de baixo é redesenhada com as MESMAS
palavras, a palavra ~1,6× e a linha ~2× maiores, na mesma fonte pixel (Jersey20) e nas mesmas cores.
Entrada: tools/xeque_src/saida_r36/ (720×1008, saída de xeque_card_counts.py). Saída: a mesma pasta
(…_legivel) e xeque/art/cartas/carta_<id>.png (360×504)."""
import io
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "tools/xeque_src/saida_r36")
GAME = os.path.join(ROOT, "xeque/art/cartas")
TEXT = {"rei": ("PEÇA", "Pode ser a peça pedida"), "rainha": ("PEÇA", "Pode ser a peça pedida"),
        "cavalo": ("PEÇA", "Pode ser a peça pedida"), "peao": ("CORINGA", "Vale como qualquer peça")}
Y0, Y1, X0, X1 = 857, 978, 30, 690
BG = (18, 10, 6)
CREAM = (238, 226, 198)


def font(size):
    f = TTFont(os.path.join(ROOT, "xeque/art/fontes/Jersey20-Regular.woff2")); f.flavor = None
    buf = io.BytesIO(); f.save(buf); buf.seek(0)
    return ImageFont.truetype(buf, size)


def spaced(d, cx, y, s, f, fill, sp):
    w = sum(d.textlength(c, font=f) for c in s) + sp * (len(s) - 1)
    x = cx - w / 2
    for c in s:
        d.text((x + 2, y + 2), c, font=f, fill=(0, 0, 0))
        d.text((x, y), c, font=f, fill=fill)
        x += d.textlength(c, font=f) + sp


for n, (word, line) in TEXT.items():
    im = Image.open(os.path.join(SRC, "carta_%s.png" % n)).convert("RGBA")
    a = np.array(im).astype(np.int32)
    reg = a[Y0:Y0 + 66, X0:X1, :3].reshape(-1, 3)
    sat = reg.max(axis=1) - reg.min(axis=1)
    col = tuple(int(v) for v in np.median(reg[sat > 60], axis=0))
    a[Y0:Y1, X0:X1, :3] = BG
    im = Image.fromarray(a.astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(im)
    fw = font(64)
    spaced(d, 360, Y0 - 6, word, fw, col, 10)
    size = 52
    fl = font(size)
    while d.textlength(line, font=fl) > X1 - X0 - 24 and size > 30:
        size -= 1; fl = font(size)
    spaced(d, 360, Y0 + 56, line, fl, CREAM, 1)
    im.save(os.path.join(SRC, "carta_%s_legivel.png" % n))
    im.resize((360, 504), Image.LANCZOS).save(os.path.join(GAME, "carta_%s.png" % n))
print("ok")
