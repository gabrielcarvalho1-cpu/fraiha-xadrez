#!/usr/bin/env python3
"""R54 · Telas de fim de partida / confirmação do PC (Web desktop) a partir das referências aprovadas
em tools/ui_ref/desk/ (fundo transparente). O que é vivo sai da arte (o jogo desenha por cima com as
mesmas fontes): modo/motivo, PL, liga, barra, nome, retrato, textos que mudam por modo. Títulos e
botões de texto fixo ficam na arte (fidelidade). Saída: ranked/art/desk_*.png (escala ART_SCALE; o jogo
posiciona tudo em coordenadas da referência).
Uso: python3 tools/desk_result_art.py"""
import os, sys
import numpy as np
import cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_pages_v2 import fill_smooth

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, 'tools', 'ui_ref', 'desk')
OUT = os.path.join(ROOT, 'ranked', 'art')
ART_SCALE = 0.75

def load(n):
    a = np.array(Image.open(os.path.join(REF, n + '.png')).convert('RGBA')).astype(np.float64)
    return a[..., :3].copy(), a[..., 3].copy()

def save(rgb, al, n, scale=ART_SCALE):
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(al, 0, 255)]).astype(np.uint8), 'RGBA')
    if scale != 1.0:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    img.save(os.path.join(OUT, n + '.png'), optimize=True)
    print(n, img.size)

def erase(a, boxes, **kw):
    for b in boxes:
        a = fill_smooth(a, b, ring=kw.get('ring', 5), thr=kw.get('thr', 70), sigma=kw.get('sigma', 18), green=kw.get('green', True))
    return a

def empty_track(a, x0, x1, y0, y1, src_x):
    """Barra de PL vazia: o trilho escuro do fim da barra (src_x..) esticado por toda a largura."""
    out = a.copy()
    col = a[y0:y1, src_x:src_x + 12].mean(axis=1)          # uma coluna média: trilho liso, sem emendas
    out[y0:y1, x0:x1] = col[:, None, :]
    return out

def bar_fill(a, x0, y0, y1, n):
    """Pedaço do preenchimento dourado (repetível) para a barra viva."""
    rgb = a[y0:y1, x0:x0 + 64]
    save(rgb, np.full(rgb.shape[:2], 255.0), n, 1.0)

# ---------------------------------------------------------------- DESISTIR (botão e modal)
def build_resign():
    rgb, al = load('desistir_botao')
    ys, xs = np.where(al > 8)
    rgb, al = rgb[ys.min():ys.max() + 1, xs.min():xs.max() + 1], al[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    save(rgb, al, 'desk_resign_btn', 0.3)
    rgb, al = load('desistir_modal')
    rgb = erase(rgb, [(178, 541, 1078, 718)], sigma=26)          # texto explicativo (muda por modo)
    save(rgb, al, 'desk_resign_modal')

# ---------------------------------------------------------------- VITÓRIA / DERROTA (Ranked e Casual)
def build_result(src, name, b):
    rgb, al = load(src)
    base = erase(rgb, [b['sub'], b['pl'], b['league'], b['count'], b['back']])
    base = empty_track(base, *b['track'])
    save(base, al, 'desk_%s_ranked' % name)
    cas = erase(base, [b['flour_l'], b['flour_r'], b['sep'], b['bar']], sigma=24)
    save(cas, al, 'desk_%s_casual' % name)
    return rgb

WIN = {'sub': (325, 540, 795, 595), 'pl': (398, 594, 728, 702), 'league': (450, 705, 675, 757),
       'count': (462, 785, 662, 832), 'back': (408, 1176, 818, 1232),
       'track': (232, 886, 838, 878, 846),
       'flour_l': (326, 615, 396, 695), 'flour_r': (730, 615, 800, 695), 'sep': (404, 758, 718, 784),
       'bar': (186, 818, 940, 896)}
LOSS = {'sub': (310, 532, 812, 584), 'pl': (412, 600, 708, 690), 'league': (446, 702, 676, 756),
        'count': (462, 782, 660, 828), 'back': (412, 1182, 808, 1236),
        'track': (232, 888, 843, 882, 848),
        'flour_l': (0, 0, 1, 1), 'flour_r': (0, 0, 1, 1), 'sep': (398, 757, 722, 783),
        'bar': (190, 826, 936, 896)}

# ---------------------------------------------------------------- ADVERSÁRIO ENCONTRADO
def build_found():
    rgb, al = load('adversario_encontrado')
    rgb = erase(rgb, [(325, 962, 800, 1048), (335, 1076, 790, 1128), (225, 1146, 900, 1204), (405, 1222, 720, 1280)])
    # miolo do retrato (o anel dourado fica): disco escuro liso; o jogo desenha o avatar recortado em círculo
    yy, xx = np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]]
    disc = (xx - 562.5) ** 2 + (yy - 829.5) ** 2 <= 104 ** 2
    rgb[disc] = (11, 26, 38)
    save(rgb, al, 'desk_found')

def fill_separable_gold(a, box):
    """Placa dourada com degradê vertical: cada linha recebe a média das colunas logo fora da caixa
    (esquerda e direita), com uma leve variação horizontal suave."""
    x0, y0, x1, y1 = box
    out = a.copy()
    left = a[y0:y1, x0 - 14:x0 - 4].mean(axis=1)
    right = a[y0:y1, x1 + 4:x1 + 14].mean(axis=1)
    t = np.linspace(0, 1, x1 - x0)[None, :, None]
    row = left[:, None, :] * (1 - t) + right[:, None, :] * t
    row = cv2.GaussianBlur(row, (1, 7), 0) if row.shape[0] > 7 else row
    m = np.zeros((y1 - y0, x1 - x0)); m[2:-2, 2:-2] = 1
    m = cv2.GaussianBlur(m, (5, 5), 0)[..., None]
    out[y0:y1, x0:x1] = a[y0:y1, x0:x1] * (1 - m) + row * m
    return out

# ---------------------------------------------------------------- CONTRA O BOT
def build_bot():
    rgb, al = load('bot_vitoria')
    crown_rgb, crown_al = rgb[874:932, 278:338].copy(), al[874:932, 278:338].copy()
    # coroa do botão dourado em peça solta (o texto do botão é vivo e a coroa fica antes dele)
    gold = fill_separable_gold(rgb, (276, 869, 988, 929))
    lum = crown_rgb.mean(axis=2); bg = gold[874:932, 278:338].mean(axis=2)
    ca = np.clip((np.abs(lum - bg) - 6) * 12, 0, 255)
    ca = cv2.GaussianBlur(ca, (3, 3), 0.7)
    save(crown_rgb, ca, 'desk_icon_crown', 1.0)
    common = [(250, 322, 1005, 374), (478, 556, 782, 598), (470, 596, 790, 652), (378, 692, 1045, 785)]
    win = erase(rgb, common + [(408, 372, 560, 548), (690, 372, 842, 548)])
    # placa dourada do botão principal: texto (e a coroa) saem com o próprio ouro em volta
    win = fill_separable_gold(win, (276, 869, 988, 929))
    win[677:813, 213:362] = (14, 30, 24)                           # quadro da recompensa (o jogo põe o avatar)
    save(win, al, 'desk_bot_win')
    # DERROTA contra o bot (sem referência própria): mesma moldura, título DERROTA da tela de derrota,
    # um só brasão (o bot que venceu) e sem o cartão de recompensa.
    loss = erase(win, [(388, 162, 878, 296), (598, 440, 652, 494), (180, 652, 1075, 835)], sigma=30)
    drgb, dal = load('derrota')
    t = drgb[392:498, 290:856]
    ta = dal[392:498, 290:856] / 255.0
    th, tw = t.shape[:2]
    s = 92.0 / th
    t = cv2.resize(t, (int(tw * s), 92), interpolation=cv2.INTER_AREA)
    ta = cv2.resize(ta, (int(tw * s), 92), interpolation=cv2.INTER_AREA)
    x0 = 627 - t.shape[1] // 2
    y0 = 190
    reg = loss[y0:y0 + t.shape[0], x0:x0 + t.shape[1]]
    loss[y0:y0 + t.shape[0], x0:x0 + t.shape[1]] = reg * (1 - ta[..., None]) + t * ta[..., None]
    save(loss, al, 'desk_bot_loss')

if __name__ == '__main__':
    build_resign()
    v = build_result('vitoria', 'win', WIN)
    bar_fill(v, 250, 842, 876, 'desk_bar_fill')
    build_result('derrota', 'loss', LOSS)
    build_found()
    build_bot()
