"""R65 · MARCHA REAL no PC: laterais da arte (mesa e salão) para janelas mais largas que 16:9.

Cada lateral é feita com uma faixa LIMPA da borda da própria arte (sem painéis, ícones ou textos), espelhada em
vai-e-vem até a largura PAD. Onde a borda tem interface desenhada (painel do relógio, ícones, painel "Você"),
usa-se a faixa estreita de cenário que sobra entre a interface e a borda. As emendas entre faixas são misturadas
na vertical e a lateral escurece um pouco para fora (foco no centro). O miolo é a arte original, sem mudança.
Saídas: marcha/art/r57/mesa_wide.png e salao_wide.png (largura + 2*PAD).
Uso: python3 tools/marcha_wide_r65.py [raiz_do_repo]"""
import sys
import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
A = ROOT + '/marcha/art/r57/'
PAD = 260
BLEND = 18
# (y_inicio, largura da faixa limpa a partir da borda)
SPECS = {
    'mesa': {'left': [(0, 130), (630, 28)], 'right': [(0, 20), (95, 122), (775, 24)]},
    'salao': {'left': [(0, 105)], 'right': [(0, 24), (80, 114)]},
}


def side(img, segs, right):
    h, w, _ = img.shape
    out = np.zeros((h, PAD, 3), np.float64)
    layers = []
    for k, (y0, sw) in enumerate(segs):
        d = np.arange(PAD)
        t = d % (2 * sw)
        idx = np.where(t < sw, t, 2 * sw - 1 - t)
        cols = (w - 1 - idx) if right else idx
        band = img[:, cols].astype(np.float64)          # coluna d = distância da borda
        layers.append((y0, band))
    # peso de cada faixa por linha (mistura suave nas emendas)
    ys = np.arange(h)
    weights = []
    for k, (y0, band) in enumerate(layers):
        y1 = layers[k + 1][0] if k + 1 < len(layers) else h
        wk = np.clip((ys - y0 + BLEND / 2) / BLEND, 0, 1) if k > 0 else np.ones(h)
        if k + 1 < len(layers): wk = wk * np.clip((y1 + BLEND / 2 - ys) / BLEND, 0, 1)
        weights.append(wk)
    tot = np.sum(weights, axis=0) + 1e-9
    for (y0, band), wk in zip(layers, weights):
        out += band * (wk / tot)[:, None, None]
    fade = 1.0 - 0.28 * (np.arange(PAD) / (PAD - 1.0)) ** 1.3       # escurece para fora
    out *= fade[None, :, None]
    if not right: out = out[:, ::-1]                                  # coluna 0 = ponta de fora
    return out


for name, spec in SPECS.items():
    img = np.asarray(Image.open(A + name + '.png').convert('RGB'))
    left = side(img, spec['left'], False)
    right = side(img, spec['right'], True)
    wide = np.concatenate([left, img.astype(np.float64), right], axis=1)
    Image.fromarray(np.clip(wide + 0.5, 0, 255).astype(np.uint8)).save(A + name + '_wide.png', optimize=True)
    print(name, wide.shape)
