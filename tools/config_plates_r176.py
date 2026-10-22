#!/usr/bin/env python3
"""R176.8 · CONFIGURAÇÕES: as 2 placas largas (PRÉ-MOVE, TABULEIRO E PEÇAS) viram 4 placas em 2x2 (+ EMOTES e TERMOS),
no mesmo desenho: a placa limpa do TABULEIRO E PEÇAS (y 930) cortada em 3 partes (pontas inteiras, miolo na largura
certa). O ícone do monitor (PRÉ-MOVE), que era pintado na 1ª placa, sai num PNG próprio.
Saída: ui_kit/pages/config_bg_r176.png e ui_kit/pages/config_ico_premove.png"""
from PIL import Image

SRC = "ui_kit/pages/config_bg.png"
im = Image.open(SRC).convert("RGBA")
PL = (126, 930, 1322, 1060)         # placa limpa (sem ícone)
plate = im.crop(PL)
H = plate.height
L, R = 84, 104                      # pontas: esquerda (cantos) e direita (cantos + seta)
icon = im.crop((180, 792, 300, 902))
icon.save("ui_kit/pages/config_ico_premove.png")
out = im.copy()
# fundo azul por baixo de tudo (faixa logo à esquerda das placas, repetida)
strip = im.crop((100, 782, 122, 1060))
for x in range(122, 1330, 22):
    out.paste(strip, (x, 782))
W = (PL[2] - PL[0] - 14) // 2
def half(w):
    h = Image.new("RGBA", (w, H))
    h.paste(plate.crop((0, 0, L, H)), (0, 0))
    mid = plate.crop((L, 0, L + (w - L - R), H))
    h.paste(mid, (L, 0))
    h.paste(plate.crop((plate.width - R, 0, plate.width, H)), (w - R, 0))
    return h
hp = half(W)
for y in (782, 930):
    out.alpha_composite(hp, (PL[0], y))
    out.alpha_composite(hp, (PL[2] - W, y))
out.save("ui_kit/pages/config_bg_r176.png")
print("ok", W)
