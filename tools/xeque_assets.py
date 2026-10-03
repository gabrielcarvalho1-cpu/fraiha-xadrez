"""Xeque · versões do jogo das artes aprovadas (mesmos pixels, só reduzidas para o tamanho em
que aparecem na tela, para não serrilhar ao encolher no navegador):
  cartas 720x1008 -> 360x504 · relógio com efeito 1200x1120 -> 600x560.
Rodar depois de tools/xeque_card_labels.py."""
import os, glob
from PIL import Image
ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "tools/xeque_src")
ART = os.path.join(ROOT, "xeque/art")
os.makedirs(os.path.join(ART, "cartas"), exist_ok=True)
for n in ["rei", "rainha", "cavalo", "peao"]:
    Image.open(os.path.join(SRC, "saida/carta_%s.png" % n)).resize((360, 504), Image.LANCZOS).save(os.path.join(ART, "cartas/carta_%s.png" % n))
Image.open(os.path.join(SRC, "carta_verso.png")).resize((360, 504), Image.LANCZOS).save(os.path.join(ART, "cartas/carta_verso.png"))
for p in glob.glob(os.path.join(SRC, "relogio/relogio_*.png")):
    Image.open(p).resize((600, 560), Image.LANCZOS).save(os.path.join(ART, "relogio", os.path.basename(p)))
print("ok")

# botões aprovados (400x120) trazem o texto desenhado ("JOGAR CARTAS", "VOLTAR"); o jogo escreve o
# texto por cima (ESPECIFICACAO.md §6), então o miolo de cada linha recebe a cor da própria linha
# (o degradê do botão é só vertical): mesmas bordas, cantos e brilho.
import numpy as np
for n in ["dourado", "escuro"]:
    a = np.array(Image.open(os.path.join(SRC, "botao_%s.png" % n)).convert("RGBA"))
    for y in range(a.shape[0]):
        a[y, 32:368] = a[y, 30]
    Image.fromarray(a).save(os.path.join(ART, "interface/botao_%s.png" % n))
print("botões sem texto")
