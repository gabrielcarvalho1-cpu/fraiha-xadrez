"""R36 · XEQUE: o selo do canto das cartas mostra a QUANTIDADE no baralho (Rei 6, Rainha 6, Cavalo 6,
Peão 2) no lugar do algarismo romano (que parecia quantidade), e o "×6/×2" do outro canto sai (não repete).
O Peão ganha uma faixa "★ CORINGA ★" no alto (decisão do dono do projeto: deixar o coringa evidente).
Entrada: tools/xeque_src/saida/carta_<id>.png (720x1008, de tools/xeque_card_labels.py).
Saída: tools/xeque_src/saida_r36/ (tamanho cheio) e xeque/art/cartas/ (360x504, versão do jogo).
Fonte do número: Jersey20 (a mesma fonte pixel do jogo; licença OFL em xeque/art/fontes/)."""
import os, io
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "tools/xeque_src/saida")
OUT = os.path.join(ROOT, "tools/xeque_src/saida_r36")
GAME = os.path.join(ROOT, "xeque/art/cartas")
os.makedirs(OUT, exist_ok=True)

def font(name, size):
    f = TTFont(os.path.join(ROOT, "xeque/art/fontes/%s.woff2" % name)); f.flavor = None
    buf = io.BytesIO(); f.save(buf); buf.seek(0)
    return ImageFont.truetype(buf, size)

COUNTS = {"rei": 6, "rainha": 6, "cavalo": 6, "peao": 2}
BADGE = (60, 58, 170, 170)          # interior do selo (cor creme com degradê vertical)
NUM = (80, 82, 146, 146)            # onde fica o algarismo romano
BOX = (588, 60, 666, 132)              # interior da caixinha escura do ×6 / ×2           # caixinha escura do ×6 / ×2
INK = (52, 26, 8)
RAY_CENTER = (360, 330)             # de onde saem os raios do fundo

for n, count in COUNTS.items():
    im = Image.open(os.path.join(SRC, "carta_%s.png" % n)).convert("RGB")
    a = np.array(im).astype(np.int32)
    # 1) apaga o algarismo: cada fileira recebe a cor creme da própria fileira (degradê preservado)
    x0, y0, x1, y1 = NUM
    for y in range(y0, y1):
        row = a[y, BADGE[0]:BADGE[2]]
        light = row[row.sum(axis=1) > 450]
        if len(light): a[y, x0:x1] = np.median(light, axis=0)
    # 2) a caixinha escura do outro canto deixa de repetir a quantidade (×6) e passa a dizer "DE 20"
    #    (6 de 20 cartas do baralho). Só o texto de dentro muda; a caixinha fica a mesma.
    bx0, by0, bx1, by1 = BOX
    box = a[by0:by1, bx0:bx1]
    light = box.min(axis=2) > 120
    dark = np.median(box[~light].reshape(-1, 3), axis=0)
    gy, gx = np.nonzero(light)
    a = a.copy()
    a[by0 + gy.min() - 3:by0 + gy.max() + 4, bx0 + gx.min() - 3:bx0 + gx.max() + 4] = dark
    glyph_box = (bx0 + gx.min(), by0 + gy.min(), bx0 + gx.max(), by0 + gy.max())
    im = Image.fromarray(a.astype(np.uint8))
    # 3) número da quantidade no selo (levemente inclinado como o selo)
    f = font("Jersey20-Regular", 84)
    layer = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((80, 80), str(count), font=f, fill=INK + (255,), anchor="mm")
    layer = layer.rotate(3, resample=Image.NEAREST)
    im = im.convert("RGBA")
    im.alpha_composite(layer, (113 - 80, 112 - 80))
    d2 = ImageDraw.Draw(im)
    gcx, gcy = (glyph_box[0] + glyph_box[2]) / 2, (glyph_box[1] + glyph_box[3]) / 2
    d2.text((gcx, gcy - 9), "DE", font=font("Jersey20-Regular", 26), fill=(240, 228, 200, 255), anchor="mm")
    d2.text((gcx, gcy + 14), "20", font=font("Jersey20-Regular", 34), fill=(255, 240, 210, 255), anchor="mm")
    if n == "peao":
        # 4) faixa CORINGA no alto da carta (verde do Peão + ouro)
        band = Image.new("RGBA", im.size, (0, 0, 0, 0))
        bd = ImageDraw.Draw(band)
        r = (190, 160, 530, 230)
        bd.rectangle((r[0] - 4, r[1] - 4, r[2] + 4, r[3] + 4), fill=(20, 10, 4, 255))
        bd.rectangle(r, fill=(232, 186, 64, 255))
        bd.rectangle((r[0] + 6, r[1] + 6, r[2] - 6, r[3] - 6), fill=(24, 120, 70, 255))
        ft = font("Jersey20-Regular", 58)
        cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
        bd.text((cx + 3, cy + 3), "CORINGA", font=ft, fill=(10, 30, 15, 255), anchor="mm")
        bd.text((cx, cy), "CORINGA", font=ft, fill=(255, 236, 160, 255), anchor="mm")
        for sx in (r[0] + 26, r[2] - 26):      # losangos dourados nas pontas
            bd.polygon([(sx, cy - 13), (sx + 13, cy), (sx, cy + 13), (sx - 13, cy)], fill=(255, 220, 110, 255), outline=(20, 10, 4, 255))
        im.alpha_composite(band)
    im = im.convert("RGB")
    im.save(os.path.join(OUT, "carta_%s.png" % n))
    im.resize((360, 504), Image.LANCZOS).save(os.path.join(GAME, "carta_%s.png" % n))
    print(n, count)
