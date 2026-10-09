#!/usr/bin/env python3
"""R55 · XEQUE no PC: cartas SEM os textos impressos (nome, palavra PEÇA/CORINGA e a linha pequena).
O jogo desenha esses textos AO VIVO por cima (xeque/xeque_view.gd · card_face), na fonte da referência
nova (Oswald) e no tamanho exato da tela: as letras ficam nítidas em qualquer janela (pedido do dono:
"deixe as escritas das cartas bem nítidas"). Arte, número e moldura ficam com os mesmos pixels.
Entrada: tools/xeque_src/saida_r36/carta_<id>.png (720x1008). Saída: xeque/art/cartas/carta_<id>_limpa.png
(720x1008) e xeque/art/cartas/cartas_r55_cores.json (cores das palavras, medidas na arte).
Uso: python3 tools/xeque_card_blank_r55.py"""
import json
import os
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "tools/xeque_src/saida_r36")
OUT = os.path.join(ROOT, "xeque/art/cartas")
IDS = ["rei", "rainha", "cavalo", "peao"]
# faixa do nome (entre o filete dourado e o filete colorido) e faixa da legenda (fundo liso)
NAME = (62, 734, 658, 846)       # x0, y0, x1, y1
LEGEND = (34, 857, 686, 978)


def blank(n):
    a = np.array(Image.open(os.path.join(SRC, "carta_%s.png" % n)).convert("RGBA"))
    rgb = a[..., :3].copy()
    x0, y0, x1, y1 = NAME
    band = rgb[y0:y1, x0:x1].astype(np.float32)
    lum = band.mean(axis=2)
    # letras (creme) e a sombra escura delas: a caixa inteira do texto (+ folga) vira o fundo da faixa,
    # linha a linha (mediana das colunas sem texto), com borda esfumada — sem "fantasma" das letras
    cols = np.nonzero((lum > 150).any(axis=0))[0]
    tx0, tx1 = max(0, cols.min() - 22), min(band.shape[1], cols.max() + 30)
    free = np.r_[0:max(1, tx0 - 4), min(band.shape[1] - 1, tx1 + 4):band.shape[1]]
    row = np.median(band[:, free], axis=1)                      # cor de cada linha da faixa
    fill = np.repeat(row[:, None, :], band.shape[1], axis=1)
    w = np.zeros(band.shape[:2], np.float32)
    w[6:-4, tx0:tx1] = 1.0
    w = cv2.GaussianBlur(w, (0, 0), 7.0)
    w[6:-4, tx0 + 14:tx1 - 14] = 1.0
    band = band * (1 - w[..., None]) + fill * w[..., None]
    rgb[y0:y1, x0:x1] = np.clip(band, 0, 255).astype(np.uint8)
    # palavra colorida: cor mediana dos pixels saturados da legenda (antes de apagar)
    lx0, ly0, lx1, ly1 = LEGEND
    leg = a[ly0:ly1, lx0:lx1, :3].reshape(-1, 3).astype(np.int32)
    sat = leg.max(axis=1) - leg.min(axis=1)
    word = np.median(leg[sat > 70], axis=0).astype(int).tolist()
    bg = np.median(a[ly0:ly1, lx0:lx0 + 12, :3].reshape(-1, 3), axis=0).astype(np.uint8)
    rgb[ly0:ly1, lx0:lx1] = bg
    out = np.dstack([rgb, a[..., 3]])
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "carta_%s_limpa.png" % n), optimize=True)
    return {"word": "#%02x%02x%02x" % tuple(word), "legend_bg": "#%02x%02x%02x" % tuple(int(v) for v in bg)}


if __name__ == "__main__":
    cores = {n: blank(n) for n in IDS}
    with open(os.path.join(OUT, "cartas_r55_cores.json"), "w") as f:
        json.dump(cores, f, indent=1)
    print(json.dumps(cores))
