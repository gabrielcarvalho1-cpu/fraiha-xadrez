"""Blefe Real · cartas do jogo a partir das cartas aprovadas (tools/blefe_src/, 720x1008).
Regra escolhida pelo dono do projeto: a mesa pede Rei, Rainha ou Cavalo e o PEÃO (Peão Coroado)
é o coringa. As cartas aprovadas trazem outra regra impressa na faixa de legenda (Rainha=CORINGA,
Rei=PERIGO, Peão=PEÇA). Só essa faixa (palavra colorida + linha pequena) é trocada; o resto da
carta fica com os mesmos pixels. Os textos novos são os PRÓPRIOS pixels das outras cartas do
pacote (CORINGA/"Vale como qualquer peça" da Rainha; PEÇA/"Pode ser a peça pedida" do Cavalo),
com a palavra recolorida na cor de cada carta. Saída: tools/blefe_src/saida/carta_<id>.png (tools/blefe_assets.py gera as versões do jogo)"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "tools/blefe_src")
OUT = os.path.join(ROOT, "tools/blefe_src/saida")   # tamanho cheio; tools/blefe_assets.py reduz para o jogo
Y0, Y1, YS = 860, 976, 922            # faixa da legenda; YS separa palavra / linha pequena
X0, X1 = 34, 686

def load(n):
    return np.array(Image.open(os.path.join(SRC, "carta_%s.png" % n)).convert("RGB")).astype(np.int32)

def bg_of(a):
    return np.median(a[Y0:Y1, X0:X0 + 20].reshape(-1, 3), axis=0)

def word_color(a):
    reg = a[Y0:YS, X0:X1].reshape(-1, 3)
    sat = reg.max(axis=1) - reg.min(axis=1)
    return np.median(reg[sat > 60], axis=0)

def relabel(target, source):
    t, s = load(target), load(source)
    out = t.copy()
    tb, sb = bg_of(t), bg_of(s)
    out[Y0:Y1, X0:X1] = tb
    reg = s[Y0:Y1, X0:X1]
    diff = np.abs(reg - sb).sum(axis=2)
    mask = diff > 30
    tw, sw = word_color(t), word_color(s)
    band = out[Y0:Y1, X0:X1]
    for y, x in zip(*np.nonzero(mask)):
        px = reg[y, x]
        if y + Y0 < YS:
            # palavra: mesma luz do pixel de origem, na cor da carta de destino
            k = (px - sb).sum() / max(1.0, (sw - sb).sum())
            band[y, x] = np.clip(tb + (tw - tb) * k, 0, 255)
        else:
            band[y, x] = px
    return out.astype(np.uint8)

os.makedirs(OUT, exist_ok=True)
plan = {"rainha": "cavalo", "rei": "cavalo", "peao": "rainha"}
for n in ["rei", "rainha", "cavalo", "peao"]:
    img = relabel(n, plan[n]) if n in plan else load(n).astype(np.uint8)
    Image.fromarray(img).save(os.path.join(OUT, "carta_%s.png" % n))
    print("carta_%s.png" % n, "(faixa de " + plan[n] + ")" if n in plan else "(sem alteração)")

# ---- quantidade no selo do canto (×N): baralho do Blefe Real = 6 Rei, 6 Rainha, 6 Cavalo, 2 Peão.
# O "×" vem dos pixels do Cavalo; o número é a mesma fonte do pacote (Jersey 20, corpo 56 — o "5"
# do Cavalo bate 99% pixel a pixel com essa fonte).
from PIL import ImageFont, ImageDraw
from fontTools.ttLib import TTFont
import tempfile
_tt = os.path.join(tempfile.gettempdir(), "jersey20_blefe.ttf")
_f = TTFont(os.path.join(ROOT, "blefe/art/fontes/Jersey20-Regular.woff2")); _f.flavor = None; _f.save(_tt)
FONT = ImageFont.truetype(_tt, 56)
BX0, BX1, BY0, BY1 = 588, 652, 72, 118          # área do texto dentro do selo
cav = load("cavalo")
cav_mask = cav[BY0:BY1, BX0:BX1].min(axis=2) > 150
cream = np.median(cav[BY0:BY1, BX0:BX1][cav_mask], axis=0)
times = cav_mask.copy(); times[:, 621 - BX0:] = False   # só o "×"

def badge(n, digit):
    p = os.path.join(OUT, "carta_%s.png" % n)
    a = np.array(Image.open(p).convert("RGB")).astype(np.int32)
    reg = a[BY0:BY1, BX0:BX1]
    txt = reg.min(axis=2) > 150
    d = txt.copy()                                   # dilata 1 px: limpa a borda suave do glifo antigo
    d[1:] |= txt[:-1]; d[:-1] |= txt[1:]; d[:, 1:] |= txt[:, :-1]; d[:, :-1] |= txt[:, 1:]
    txt = d
    # apaga o texto antigo: cada pixel recebe o fundo da mesma linha
    for y in range(reg.shape[0]):
        bgx = np.nonzero(~txt[y])[0]
        for x in np.nonzero(txt[y])[0]:
            near = bgx[np.argsort(np.abs(bgx - x))[:4]]
            reg[y, x] = reg[y, near].mean(axis=0)
    reg[times] = cream
    im = Image.new("L", (120, 120), 0)
    ImageDraw.Draw(im).text((10, 10), digit, font=FONT, fill=255)
    g = np.array(im) > 128
    ys, xs = np.nonzero(g); g = g[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    oy, ox = 111 - BY0 - g.shape[0] + 1, 644 - BX0 - g.shape[1] + 1
    sub = reg[oy:oy + g.shape[0], ox:ox + g.shape[1]]
    sub[g] = cream
    a[BY0:BY1, BX0:BX1] = reg
    Image.fromarray(a.astype(np.uint8)).save(p)
    print("carta_%s.png selo ×%s" % (n, digit))

for n, d in [("rei", "6"), ("rainha", "6"), ("cavalo", "6"), ("peao", "2")]:
    badge(n, d)
