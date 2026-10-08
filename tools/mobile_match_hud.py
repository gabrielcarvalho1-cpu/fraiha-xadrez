#!/usr/bin/env python3
"""R53 · HUD da partida no CELULAR (em pé e deitado) a partir das referências aprovadas:
tools/ui_ref/mobile/mob_partida_portrait.png (941 x 1672) e mob_partida_landscape.png (1672 x 941).
O que é vivo sai da arte e o jogo desenha por cima: peças (as casas da referência são refeitas com casas limpas
da própria arte), retratos, nomes, liga/modo, relógios. Botões e o painel AÇÕES viram peças separadas (o jogo
monta só as ações que existem naquela partida). Saída: ranked/art/mob_*.png
Uso: python3 tools/mobile_match_hud.py"""
import os, sys
import numpy as np
import cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_pages_v2 import fill_smooth

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, 'tools', 'ui_ref', 'mobile')
OUT = os.path.join(ROOT, 'ranked', 'art')

# casas do tabuleiro na referência (x0, y0, x1, y1), medidas pelas bordas verde/areia
P_BOARD = (123.5, 250.5, 811.0, 917.5)
L_BOARD = (508.5, 133.0, 1168.5, 776.0)

def load(n):
    return np.array(Image.open(os.path.join(REF, n + '.png')).convert('RGB')).astype(np.float64)

def save(a, n, alpha=None):
    a = np.clip(a, 0, 255)
    if alpha is None: img = Image.fromarray(a.astype(np.uint8), 'RGB')
    else: img = Image.fromarray(np.dstack([a, np.clip(alpha, 0, 255)]).astype(np.uint8), 'RGBA')
    img.save(os.path.join(OUT, n + '.png'), optimize=True)
    print(n, img.size)

def colcopy(a, box, src_x):
    x0, y0, x1, y1 = box
    out = a.copy()
    out[y0:y1, x0:x1] = a[y0:y1, src_x:src_x + 1]
    return out

def clean_board(a, board, marked=()):
    """Casas com peça (fileiras 1, 2, 7, 8) ou marca (lance/ponto) recebem uma casa vazia da mesma cor,
    da própria arte (fileiras 3 a 6). A grama de cada casa continua variada."""
    x0, y0, x1, y1 = board
    cw, ch = (x1 - x0) / 8.0, (y1 - y0) / 8.0
    def cell(r, c):
        return (int(round(x0 + c * cw)), int(round(y0 + r * ch)), int(round(x0 + (c + 1) * cw)), int(round(y0 + (r + 1) * ch)))
    out = a.copy()
    clean = [(r, c) for r in range(2, 6) for c in range(8) if (r, c) not in marked]
    for r in range(8):
        for c in range(8):
            if 2 <= r <= 5 and (r, c) not in marked: continue
            par = (r + c) % 2
            cands = [rc for rc in clean if (rc[0] + rc[1]) % 2 == par]
            sr, sc = min(cands, key=lambda rc: (abs(rc[1] - c), abs(rc[0] - r)))
            tx0, ty0, tx1, ty1 = cell(r, c)
            sx0, sy0, sx1, sy1 = cell(sr, sc)
            src = a[sy0 + 2:sy1 - 2, sx0 + 2:sx1 - 2]          # sem a linha da casa vizinha
            # espelha às vezes: a mesma casa repetida não fica idêntica
            if (r * 3 + c) % 2: src = src[:, ::-1]
            out[ty0:ty1, tx0:tx1] = cv2.resize(src, (tx1 - tx0, ty1 - ty0), interpolation=cv2.INTER_LINEAR)
    return out

def disc(a, cx, cy, r, color):
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    m = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    out = a.copy(); out[m] = color
    return out

def ink(a, box, thr=105):
    """Ícone dourado/creme sobre fundo escuro: alpha pelo brilho (com borda suave)."""
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    l = sub.max(axis=2)
    m = (l > thr).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    al = cv2.GaussianBlur(m.astype(np.float64) * 255.0, (3, 3), 0.8)
    return sub, al

def blockcopy(a, box, src_off):
    """Troca a caixa por um pedaço vizinho do cenário (folhagem), com borda suave."""
    x0, y0, x1, y1 = box
    dx, dy = src_off
    out = a.copy()
    src = a[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
    m = np.ones((y1 - y0, x1 - x0))
    m = cv2.GaussianBlur(np.pad(m, 6), (13, 13), 4)[6:-6, 6:-6]
    m = np.clip((m - 0.5) * 2.2 + 0.5, 0, 1)[..., None]
    out[y0:y1, x0:x1] = a[y0:y1, x0:x1] * (1 - m) + src * m
    return out

# ---------------------------------------------------------------- EM PÉ
def build_portrait():
    a = load('mob_partida_portrait')
    dark = np.array([12, 30, 20], np.float64)
    b = clean_board(a, P_BOARD, marked={(4, 7), (5, 7), (6, 7)})
    # cartão do adversário: retrato, nome, modo e relógio (vivos)
    b = disc(b, 205, 126, 41, dark)
    b = fill_smooth(b, (258, 84, 470, 164), ring=4, thr=70, sigma=18, green=True)
    b = fill_smooth(b, (686, 94, 812, 160), ring=4, thr=70, sigma=16, green=True)
    # cartão do jogador
    b[976:1070, 111:220] = dark
    b = fill_smooth(b, (232, 976, 352, 1060), ring=4, thr=70, sigma=18, green=True)
    b = fill_smooth(b, (698, 988, 816, 1058), ring=4, thr=70, sigma=16, green=True)
    top = b[0:1092]
    fade = np.full(top.shape[:2], 255.0)
    fade[-36:] = np.linspace(255, 0, 36)[:, None]        # chão da floresta some suave no fundo da tela
    fade[:24] = np.minimum(fade[:24], np.linspace(0, 255, 24)[:, None])
    save(top, 'mob_hud_p_top', fade)                     # cartões + tabuleiro (o resto da tela é do layout)
    # moldura do tabuleiro sozinha (sem cartões): o tabuleiro do celular DEITADO
    core = b[180:952, 96:846]
    al = np.full(core.shape[:2], 255.0)
    for i in range(10):
        f = 255.0 * (i + 1) / 11.0
        al[:, i] = np.minimum(al[:, i], f); al[:, -1 - i] = np.minimum(al[:, -1 - i], f)
    save(core, 'mob_hud_frame', al)
    # cartão liso (moldura dourada + miolo), caixa do relógio (ampulheta) e aro do retrato: peças soltas
    card = b[64:184, 128:842].copy()
    card[:, 22:706] = card[:, 432:433]
    save(card, 'mob_hud_card')
    save(b[72:174, 610:840], 'mob_hud_clockbox')
    sub, al = ink(a, (636, 92, 684, 156), 100)            # ampulheta (relógio dos cartões soltos)
    save(sub, 'mob_hud_ico_hourglass', al)
    ring = a[126 - 50:126 + 50, 205 - 50:205 + 50]
    yy, xx = np.mgrid[0:100, 0:100]
    d = np.hypot(xx - 49.5, yy - 49.5)
    ral = np.clip((47.5 - d) * 255, 0, 255) * np.clip((d - 37.5) * 255, 0, 255) / 255.0
    save(ring, 'mob_hud_ring', ral)
    # barra de baixo (INÍCIO · AÇÕES · CHAT): ícones e rótulos saem (o jogo desenha); a moldura fica
    n = a.copy()
    for box in [(222, 1516, 360, 1616), (583, 1516, 720, 1616)]:
        n = fill_smooth(n, box, ring=5, thr=70, sigma=18, green=True)
    n = fill_smooth(n, (414, 1510, 544, 1616), ring=4, thr=75, sigma=20, green=True)   # miolo do AÇÕES (aceso)
    save(n[1480:1672], 'mob_hud_p_nav')
    for nm, box in [('home', (262, 1522, 318, 1578)), ('bars', (436, 1512, 524, 1578)), ('chat', (616, 1520, 684, 1574))]:
        sub, al = ink(a, box, 110)
        save(sub, 'mob_hud_ico_' + nm, al)
    # painel AÇÕES: moldura (sem a plaquinha e o X, que vêm à parte) e o miolo liso
    p = a.copy()
    p = fill_smooth(p, (60, 1186, 884, 1468), ring=6, thr=70, sigma=40, green=True)
    p = colcopy(p, (300, 1098, 652, 1192), 200)
    p = colcopy(p, (812, 1098, 906, 1196), 760)
    box = (20, 1100, 921, 1490)
    pal = np.zeros((box[3] - box[1], box[2] - box[0]))
    pal[1132 - box[1]:1488 - box[1], 24 - box[0]:917 - box[0]] = 255.0
    pal = cv2.GaussianBlur(pal, (3, 3), 0.8)
    save(p[box[1]:box[3], box[0]:box[2]], 'mob_hud_panel', pal)
    save(a[1100:1184, 338:612], 'mob_hud_plaque')         # plaquinha AÇÕES (texto fixo)
    save(a[1112:1194, 832:916], 'mob_hud_close')          # X
    tl = fill_smooth(a, (490, 1200, 656, 1312), ring=5, thr=70, sigma=24, green=True)
    save(tl[1190:1322, 478:668], 'mob_hud_tile')
    icons = {'flag': (126, 1202, 204, 1270), 'mark': (330, 1198, 414, 1272), 'music': (536, 1202, 600, 1268),
             'fx': (738, 1206, 810, 1264), 'mic': (144, 1338, 196, 1410), 'full': (338, 1340, 404, 1404)}
    # (Configurações e Ajuda da referência não têm ação no jogo: não viram ladrilho — nada de botão falso)
    for nm, bx in icons.items():
        sub, al = ink(a, bx, 112)
        save(sub, 'mob_hud_ico_' + nm, al)

# ---------------------------------------------------------------- DEITADO
def build_landscape():
    a = load('mob_partida_landscape')
    dark = np.array([12, 30, 20], np.float64)
    b = clean_board(a, L_BOARD, marked={(4, 7), (6, 7)})
    # cartões: retrato, brasão, nome, modo e relógio (vivos)
    b = disc(b, 605, 60, 47, dark)
    b = colcopy(b, (662, 20, 936, 96), 938)
    b = fill_smooth(b, (1008, 34, 1118, 92), ring=4, thr=70, sigma=16, green=True)
    b = disc(b, 602, 862, 47, dark)
    b = colcopy(b, (662, 824, 936, 898), 938)
    b = fill_smooth(b, (1010, 834, 1124, 896), ring=4, thr=70, sigma=16, green=True)
    # botões dos cantos e a aba AÇÕES saem da arte (vêm à parte, presos às bordas da tela)
    for nm, bx in [('back', (22, 16, 108, 100)), ('gear', (1462, 14, 1546, 98)), ('chat', (1566, 14, 1650, 98)), ('tab', (1586, 298, 1672, 592))]:
        save(a[bx[1]:bx[3], bx[0]:bx[2]], 'mob_hud_l_' + nm)
    b = blockcopy(b, (22, 16, 108, 100), (0, 96))
    b = blockcopy(b, (1462, 14, 1546, 98), (0, 100))
    b = blockcopy(b, (1566, 14, 1650, 98), (0, 100))
    b = blockcopy(b, (1586, 298, 1672, 592), (-96, 0))
    save(b, 'mob_hud_l_art')
    save(b[100:941, 1190:1672], 'mob_hud_fill')          # chão/caminho da floresta: fundo das sobras da tela

if __name__ == '__main__':
    build_portrait()
    build_landscape()
