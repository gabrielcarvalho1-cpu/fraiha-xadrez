# R198 · AMIGOS (PC) com a ARTE do dono: recorta a referência em peças e apaga só o que o jogo escreve
# (texto da busca, abas, linha de exemplo, botão), repetindo uma coluna limpa do próprio fundo.
# Uso: python3 tools/art/amigos_r198.py <referencia.png>
import sys, numpy as np
from PIL import Image
src = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).astype(np.float32)
OUT = "ui_kit/pages/amigos_r198/"
def wipe(a, x0, y0, x1, y1, cx, w=5):
    col = a[y0:y1, cx:cx + w].mean(axis=1, keepdims=True)
    a[y0:y1, x0:x1] = col
def save(a, name):
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(OUT + name, optimize=True)
    print(name, a.shape[1], a.shape[0])
# 1) moldura: sem o texto da busca e sem a área da lista (o jogo põe a lista com a moldura dela)
f = src.copy()
wipe(f, 180, 240, 785, 288, 640)
card = src[828:945, 560:880].copy()
from PIL import Image as I
fill = np.asarray(I.fromarray(card.astype(np.uint8)).resize((1336 - 112, 966 - 436), I.BICUBIC)).astype(np.float32)
f[436:966, 112:1336] = fill
save(f, "frame.png")
# 2) moldura da lista (anel dourado, miolo transparente) — 9 fatias no jogo
ring = src[436:810, 112:1336].copy()
# estica só o meio na vertical (cantos e faixas do jeito da arte) até a altura da lista (530)
H = 530; top, bot = ring[:120], ring[-120:]
mid = np.asarray(Image.fromarray(ring[120:-120].astype(np.uint8)).resize((ring.shape[1], H - 240), Image.BICUBIC)).astype(np.float32)
save(np.concatenate([top, mid, bot], 0), "list_ring.png")
# 3) linha de amigo: placa limpa (sem retrato, nome, status e botão) + moldura do retrato com o miolo vazado
row = src[810:958, 114:1334].copy()
wipe(row, 20, 12, 1200, 136, 700 - 114)
wipe(row, 575, 120, 655, 148, 540)   # tira a pontinha do losango da moldura de baixo
save(row, "row.png")
fr = src[826:954, 138:248].copy()
fr[20:110, 14:96, 3] = 0
save(fr, "avatar_frame.png")
# 4) botão azul limpo (o jogo escreve MENSAGEM / CONVIDAR / ACEITAR...)
b = src[843:933, 990:1300].copy()
wipe(b, 22, 14, 290, 76, 1018 - 990, 4)
save(b, "button.png")
# 5) abas: acesa (ONLINE) e apagada (EM PARTIDA), sem ícone e sem texto
t1 = src[325:422, 120:537].copy(); wipe(t1, 28, 16, 395, 84, 142 - 120, 4); save(t1, "tab_on.png")
t2 = src[325:422, 538:940].copy(); wipe(t2, 22, 16, 385, 84, 552 - 538, 4); save(t2, "tab_off.png")
