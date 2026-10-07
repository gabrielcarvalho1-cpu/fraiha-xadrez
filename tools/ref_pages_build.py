#!/usr/bin/env python3
"""R51 · Páginas no visual das referências do dono (tools/ui_ref/*.png).
A referência vira o FUNDO da página; o que muda com o jogo (estado, botões, nomes, números) sai da arte e o
jogo desenha por cima nas mesmas posições. Saída: ui_kit/pages/*.png (+ peças: botões, ícones).
Uso: python3 tools/ref_pages_build.py"""
import os
import numpy as np
import cv2
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, 'tools', 'ui_ref')
OUT = os.path.join(ROOT, 'ui_kit', 'pages')
os.makedirs(OUT, exist_ok=True)

def load(n): return np.array(Image.open(os.path.join(REF, n + '.png')).convert('RGB'))
def save_rgba(a, n):
    Image.fromarray(a.astype(np.uint8), 'RGBA').save(os.path.join(OUT, n + '.png'))

## R51b · Só a MOLDURA e o miolo da referência: tudo que é cenário em volta (pilares, tochas, céu, mata)
## fica transparente, para a Home do jogo aparecer em volta. O contorno dourado da moldura é a barreira:
## enche-se a partir das bordas da imagem por tudo que não é dourado; fica só o pedaço ligado ao miolo.
## inner = retângulo certamente dentro da moldura; clip = caixa externa máxima; cuts = sobras a apagar.
FRAME = {
    'hist_bg': dict(ref='historico', inner=(40, 50, 1850, 815)),
    'about_bg': dict(ref='conheca', inner=(100, 44, 1796, 795), clip=(96, 36, 1800, 829), keep=[(880, 0, 1016, 60)]),
    'config_bg': dict(ref='config', inner=(40, 80, 1310, 1140), cuts=[(0, 300, 36, 1000), (1316, 300, 1353, 1000)]),
    'bots_bg': dict(ref='bots', inner=(60, 110, 1610, 910)),
    'ligas_bg': dict(ref='ligas', inner=(60, 110, 1610, 910), cuts=[(0, 400, 55, 850), (1615, 400, 1672, 850)]),
    'perfil_bg': dict(ref='perfil', inner=(20, 40, 1210, 370)),
}
def frame_alpha(a, inner, clip=None, keep=(), cuts=()):
    r, g, b = [a[..., i].astype(int) for i in range(3)]
    gold = (r > 140) & (g > 90) & (r - b > 60) & (r >= g)
    bar = cv2.dilate(gold.astype(np.uint8) * 255, np.ones((3, 3), np.uint8))
    x0, y0, x1, y1 = inner
    bar[y0:y1, x0:x1] = 255
    h, w = bar.shape
    fm = np.zeros((h + 2, w + 2), np.uint8)
    seeds = [(x, 0) for x in range(0, w, 5)] + [(x, h - 1) for x in range(0, w, 5)] + \
            [(0, y) for y in range(0, h, 5)] + [(w - 1, y) for y in range(0, h, 5)]
    for (x, y) in seeds:
        if bar[y, x] == 0: cv2.floodFill(bar, fm, (x, y), 128)
    kept = (bar != 128).astype(np.uint8)
    _, lab = cv2.connectedComponents(kept, connectivity=8)
    kept = (lab == lab[(y0 + y1) // 2, (x0 + x1) // 2]).astype(np.uint8) * 255
    if clip is not None:
        cm = np.zeros_like(kept)
        cx0, cy0, cx1, cy1 = clip
        cm[cy0:cy1, cx0:cx1] = 255
        for (kx0, ky0, kx1, ky1) in keep: cm[ky0:ky1, kx0:kx1] = 255
        kept &= cm
    for (kx0, ky0, kx1, ky1) in cuts: kept[ky0:ky1, kx0:kx1] = 0
    _, lab = cv2.connectedComponents((kept > 0).astype(np.uint8), connectivity=8)
    kept = (lab == lab[(y0 + y1) // 2, (x0 + x1) // 2]).astype(np.uint8) * 255
    kept = cv2.dilate(kept, np.ones((3, 3), np.uint8))       # o contorno escuro do dourado fica
    return cv2.GaussianBlur(kept, (3, 3), 0)

def save(a, n):
    if n in FRAME:
        f = dict(FRAME[n])
        al = frame_alpha(load(f.pop('ref')), **f)
        rgb = a.astype(np.uint8).copy()
        rgb[al == 0] = 0
        Image.fromarray(np.dstack([rgb, al]), 'RGBA').save(os.path.join(OUT, n + '.png'))
        return
    Image.fromarray(a.astype(np.uint8)).save(os.path.join(OUT, n + '.png'))

def inpaint(a, mask, r=6):
    bgr = cv2.cvtColor(a.astype(np.uint8), cv2.COLOR_RGB2BGR)
    return cv2.cvtColor(cv2.inpaint(bgr, mask, r, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)

def lum(a): return a.astype(int).sum(axis=2) // 3

def clear_light(a, box, thr=58, grow=3, r=5):
    """Apaga (inpaint) o que é claro (texto/ícones) dentro da caixa, preservando o fundo escuro."""
    x0, y0, x1, y1 = box
    m = np.zeros(a.shape[:2], np.uint8)
    sub = lum(a[y0:y1, x0:x1]) > thr
    m[y0:y1, x0:x1] = sub.astype(np.uint8) * 255
    if grow: m = cv2.dilate(m, np.ones((grow * 2 + 1, grow * 2 + 1), np.uint8))
    m[:y0] = 0; m[y1:] = 0; m[:, :x0] = 0; m[:, x1:] = 0
    return inpaint(a, m, r)

def fill_box(a, box, src_box):
    """Preenche a caixa repetindo um retalho limpo (textura) da própria arte."""
    x0, y0, x1, y1 = box
    sx0, sy0, sx1, sy1 = src_box
    tile = a[sy0:sy1, sx0:sx1].copy()
    th, tw = tile.shape[:2]
    for y in range(y0, y1):
        for x in range(x0, x1, tw):
            w = min(tw, x1 - x)
            a[y, x:x + w] = tile[(y - y0) % th, :w]
    return a

# ======================================================================= BOTS (Desafio das Ligas)
BOT_ROW1 = [(68, 311), (328, 569), (586, 826), (843, 1084), (1102, 1342), (1358, 1601)]
BOT_ROW2 = [(68, 356), (379, 667), (690, 980), (1001, 1290), (1313, 1602)]
BOT_Y1 = (203, 512)
BOT_Y2 = (528, 804)
EMBLEM1 = (208, 338)    # faixa do escudo nos cartões de cima (y)
EMBLEM2 = (533, 652)

def plain_card(a, donor, emb_rows):
    """Cartão-base sem nada dentro (só a moldura) feito do cartão doador."""
    x0, x1, y0, y1 = donor
    c = a[y0:y1 + 1, x0:x1 + 1].copy()
    h, w = c.shape[:2]
    m = np.zeros((h, w), np.uint8)
    m[16:h - 16, 16:w - 16] = (lum(c[16:h - 16, 16:w - 16]) > 46).astype(np.uint8) * 255
    m = cv2.dilate(m, np.ones((7, 7), np.uint8))
    m[:14] = 0; m[h - 14:] = 0; m[:, :14] = 0; m[:, w - 14:] = 0
    return inpaint(c, m, 7)

def emblem_mask(c, rows, cx):
    """Máscara do escudo (claro/colorido) nas linhas rows, só perto do centro x."""
    h, w = c.shape[:2]
    m = np.zeros((h, w), np.uint8)
    y0, y1 = rows
    sub = c[y0:y1]
    l = lum(sub); sat = sub.max(axis=2).astype(int) - sub.min(axis=2).astype(int)
    fg = ((l > 52) | (sat > 40)).astype(np.uint8) * 255
    m[y0:y1] = fg
    m[:, :20] = 0; m[:, w - 20:] = 0
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    m = cv2.GaussianBlur(m, (3, 3), 0)
    return m

def build_bots():
    a = load('bots')
    out = a.copy()
    donor1 = (586, 826, BOT_Y1[0], BOT_Y1[1])          # BRONZE (sem destaque)
    donor2 = (379, 667, BOT_Y2[0], BOT_Y2[1])          # DIAMANTE
    base1 = plain_card(a, donor1, EMBLEM1)
    base2 = plain_card(a, donor2, EMBLEM2)
    for row, (y0, y1), base, er in [(BOT_ROW1, BOT_Y1, base1, EMBLEM1), (BOT_ROW2, BOT_Y2, base2, EMBLEM2)]:
        for (x0, x1) in row:
            src = a[y0:y1 + 1, x0:x1 + 1].astype(float)
            bh, bw = base.shape[:2]
            card = cv2.resize(base, (x1 - x0 + 1, y1 - y0 + 1), interpolation=cv2.INTER_NEAREST) if (bw, bh) != (x1 - x0 + 1, y1 - y0 + 1) else base.copy()
            m = emblem_mask(src.astype(np.uint8), (er[0] - y0, er[1] - y0), (x1 - x0) // 2).astype(float)[..., None] / 255.0
            card = card.astype(float) * (1 - m) + src * m
            # destaque (PRATA) sai: o anel do cartão vem do doador
            out[y0:y1 + 1, x0:x1 + 1] = card
    # o brilho dourado em volta do cartão PRATA vaza para fora: limpa o anel externo dele
    x0, x1 = BOT_ROW1[3]; y0, y1 = BOT_Y1
    ring = np.zeros(a.shape[:2], np.uint8)
    cv2.rectangle(ring, (x0 - 10, y0 - 10), (x1 + 10, y1 + 10), 255, -1)
    cv2.rectangle(ring, (x0, y0), (x1, y1), 0, -1)
    ring &= ((lum(a) > 70).astype(np.uint8) * 255)
    out = inpaint(out, cv2.dilate(ring, np.ones((3, 3), np.uint8)), 4)
    # texto "Progresso salvo na sua conta." sai (o jogo escreve o estado real do progresso)
    out = clear_light(out, (770, 848, 1560, 890), thr=60, grow=2)
    save(out, 'bots_bg')
    # peças: destaque (anel do PRATA), botões (3 estilos, sem texto) e ícones de estado
    pr = a[y0 - 10:y1 + 11, x0 - 10:x1 + 11].copy()
    hh, ww = pr.shape[:2]
    alpha = np.zeros((hh, ww), np.uint8)
    alpha[:] = 255
    alpha[28:hh - 28, 28:ww - 28] = 0
    glow = np.dstack([pr, alpha])
    # brilho: só o que é claro no anel (o resto fica transparente)
    l = lum(pr)
    glow[..., 3] = np.where((alpha > 0) & (l > 60), 255, np.where(alpha > 0, np.clip((l - 20) * 4, 0, 255), 0))
    save_rgba(glow, 'bots_glow')
    def button(box, name):
        bx0, by0, bx1, by1 = box
        b = a[by0:by1, bx0:bx1].copy()
        h, w = b.shape[:2]
        mid = b[:, w // 2 - 1:w // 2]   # coluna do meio tem texto: usa a coluna logo após as bordas
        clean = b[:, 30:31]
        b[:, 26:w - 26] = np.repeat(clean, w - 52, axis=1)
        al = np.full((h, w), 255, np.uint8)
        save_rgba(np.dstack([b, al]), name)
    button((84, 456, 298, 500), 'btn_jogar_de_novo')
    button((858, 456, 1072, 500), 'btn_desafiar')
    button((1116, 456, 1330, 500), 'btn_bloqueado')
    def icon(box, name, bg_thr=48):
        bx0, by0, bx1, by1 = box
        b = a[by0:by1, bx0:bx1].copy()
        l = lum(b); sat = b.max(axis=2).astype(int) - b.min(axis=2).astype(int)
        al = np.where((l > bg_thr) | (sat > 50), 255, 0).astype(np.uint8)
        save_rgba(np.dstack([b, al]), name)
    icon((118, 397, 146, 420), 'ico_check')
    icon((898, 396, 926, 421), 'ico_espadas_ouro')
    icon((1152, 395, 1176, 421), 'ico_cadeado')
    print('bots ok')

# ======================================================================= LIGAS (Sistema de Ligas)
LIGA_TILES = [(78, 210), (220, 349), (358, 487), (496, 625), (634, 763), (771, 900), (909, 1038), (1047, 1176),
              (1185, 1314), (1322, 1451), (1460, 1590)]
LIGA_TILE_Y = (222, 424)

SRC_LIGAS = None
def dark_fill(a, box, src_box):
    x0, y0, x1, y1 = src_box
    tile = SRC_LIGAS[y0:y1, x0:x1].copy()
    th, tw = tile.shape[:2]
    bx0, by0, bx1, by1 = box
    for y in range(by0, by1):
        for x in range(bx0, bx1, tw):
            w = min(tw, bx1 - x)
            a[y, x:x + w] = tile[(y - by0) % th, :w]
    return a

def build_ligas():
    global SRC_LIGAS
    a = load('ligas')
    SRC_LIGAS = a
    out = a.copy()
    # cabeçalho: sai "Gabriel — Madeira · 0 / 100 PL" (fica "SISTEMA DE LIGAS ·")
    out = clear_light(out, (538, 92, 1090, 142), thr=60, grow=3, r=6)
    # estado de cada liga (DISPONÍVEL / BLOQUEADA) sai
    for (x0, x1) in LIGA_TILES:
        out = clear_light(out, (x0 + 8, 388, x1 - 8, 410), thr=70, grow=2, r=4)
    # MADEIRA destacada: vira cartão comum (moldura do FERRO + brasão/nome da Madeira); o destaque é do jogo
    fx0, fx1 = LIGA_TILES[1]; y0, y1 = LIGA_TILE_Y
    plain = out[y0 - 6:y1 + 6, fx0 - 6:fx1 + 6].copy()
    mx0, mx1 = 73, 213
    ph, pw = plain.shape[:2]
    # a moldura do FERRO mede ~141 px; a da Madeira (com brilho) ~140: encaixa na mesma largura
    tgt = out[y0 - 6:y1 + 6, mx0:mx0 + pw]
    src = a[y0 - 6:y1 + 6, mx0:mx0 + pw].astype(int)
    # brasão + nome da Madeira (claro/colorido, miolo do cartão) por cima do cartão comum
    inner = np.zeros(src.shape[:2], np.uint8)
    inner[14:ph - 34, 16:pw - 16] = 1
    l = lum(src); sat = src.max(axis=2) - src.min(axis=2)
    keep = ((l > 55) | (sat > 45)) & (inner > 0)
    keep[ph - 46:] = False
    keep = cv2.morphologyEx(keep.astype(np.uint8) * 255, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)) > 0
    # cartão comum com o miolo limpo (sem o brasão/nome do Ferro)
    pc = plain.copy()
    pm = np.zeros(pc.shape[:2], np.uint8)
    sub = pc[14:ph - 34, 16:pw - 16]
    pm[14:ph - 34, 16:pw - 16] = (((lum(sub) > 46) | ((sub.max(axis=2) - sub.min(axis=2).astype(int)) > 40))).astype(np.uint8) * 255
    pm = cv2.dilate(pm, np.ones((5, 5), np.uint8))
    pc = inpaint(pc, pm, 6)
    comp = np.where(keep[..., None], src, pc)
    # nome MADEIRA: copia a faixa do nome do original (y 362..386)
    out[y0 - 6:y1 + 6, mx0:mx0 + pw] = comp
    # sobra do brilho fora do cartão da Madeira (lado esquerdo/direito/cima)
    ring = np.zeros(a.shape[:2], np.uint8)
    cv2.rectangle(ring, (66, 212), (218, 432), 255, -1)
    cv2.rectangle(ring, (mx0 + 2, y0 - 4), (mx0 + pw - 2, y1 + 4), 0, -1)
    ring &= ((lum(a) > 80).astype(np.uint8) * 255)
    out = inpaint(out, ring, 4)
    # painel da liga: brasão grande, título, chip e descrição saem (o jogo desenha a liga escolhida)
    out = dark_fill(out, (92, 462, 322, 760), (1334, 524, 1394, 548))
    out = clear_light(out, (326, 462, 880, 518), thr=58, grow=3, r=6)
    out = clear_light(out, (372, 526, 512, 553), thr=70, grow=2, r=4)
    out = clear_light(out, (336, 568, 890, 672), thr=58, grow=3, r=6)
    # painel da direita: título da liga, cenário e peças saem
    out = clear_light(out, (1060, 452, 1470, 494), thr=58, grow=3, r=6)
    out = dark_fill(out, (966, 510, 1304, 768), (1334, 524, 1394, 548))
    out = dark_fill(out, (1326, 516, 1568, 760), (1334, 524, 1394, 548))
    save(out, 'ligas_bg')
    print('ligas ok')

# ======================================================================= HISTÓRICO DE PARTIDAS
HIST_TABS = [(68, 310), (320, 590), (601, 800), (812, 1065), (1077, 1277), (1290, 1541), (1555, 1793)]
HIST_TAB_Y = (140, 207)

def clean_block(a, box, w=60, h=24):
    x0, y0, x1, y1 = box
    best = None
    f = a.astype(float)
    for y in range(y0, y1 - h, 3):
        for x in range(x0, x1 - w, 3):
            b = f[y:y + h, x:x + w]
            m = b.mean(); v = b.std()
            if m < 45 and (best is None or v < best[0]): best = (v, x, y)
    return (best[1], best[2], best[1] + w, best[2] + h)

def strip_inner(c, pad_x, pad_y, thr=55):
    """Tira ícone/texto de dentro de uma moldura (inpaint do que é claro/colorido no miolo)."""
    h, w = c.shape[:2]
    m = np.zeros((h, w), np.uint8)
    sub = c[pad_y:h - pad_y, pad_x:w - pad_x]
    sat = sub.max(axis=2).astype(int) - sub.min(axis=2).astype(int)
    m[pad_y:h - pad_y, pad_x:w - pad_x] = (((lum(sub) > thr) | (sat > 60))).astype(np.uint8) * 255
    m = cv2.dilate(m, np.ones((5, 5), np.uint8))
    m[:pad_y] = 0; m[h - pad_y:] = 0; m[:, :pad_x] = 0; m[:, w - pad_x:] = 0
    return inpaint(c, m, 5)

def cut_icon(a, box, thr=60):
    x0, y0, x1, y1 = box
    b = a[y0:y1, x0:x1].copy()
    l = lum(b); sat = b.max(axis=2).astype(int) - b.min(axis=2).astype(int)
    al = np.where((l > thr) | (sat > 70), 255, 0).astype(np.uint8)
    al = cv2.morphologyEx(al, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    ys, xs = np.where(al > 0)
    if len(xs):
        b = b[ys.min():ys.max() + 1, xs.min():xs.max() + 1]; al = al[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return np.dstack([b, al])

def build_historico():
    a = load('historico')
    out = a.copy()
    src = clean_block(a, (300, 210, 1800, 232), 40, 10)
    def fill(box):
        x0, y0, x1, y1 = src
        tile = a[y0:y1, x0:x1]
        th, tw = tile.shape[:2]
        bx0, by0, bx1, by1 = box
        for y in range(by0, by1):
            for x in range(bx0, bx1, tw):
                ww = min(tw, bx1 - x)
                out[y, x:x + ww] = tile[(y - by0) % th, :ww]
    # abas e lista saem (o jogo desenha); o fundo da lista fica escuro como o painel
    fill((60, 134, 1800, 214))
    fill((62, 220, 1798, 734))
    save(out, 'hist_bg')
    # moldura das abas: comum (COMPUTADOR) e escolhida (TODAS), sem ícone/texto
    ty0, ty1 = HIST_TAB_Y
    tc = strip_inner(a[ty0:ty1, 320:591].copy(), 10, 10)
    save_rgba(np.dstack([tc, np.full(tc.shape[:2], 255, np.uint8)]), 'hist_tab')
    ts = strip_inner(a[ty0 - 2:ty1 + 2, 64:314].copy(), 12, 12)
    save_rgba(np.dstack([ts, np.full(ts.shape[:2], 255, np.uint8)]), 'hist_tab_sel')
    # ícones das abas (também usados nas linhas)
    for name, box in [('ico_todas', (95, 150, 140, 198)), ('ico_computador', (340, 150, 392, 198)), ('ico_online', (622, 150, 672, 198)),
                      ('ico_ranqueada', (834, 150, 884, 198)), ('ico_local', (1098, 150, 1148, 198)), ('ico_marcha', (1310, 150, 1360, 198)),
                      ('ico_xeque', (1574, 150, 1634, 198))]:
        save_rgba(cut_icon(a, box), name)
    # linhas: vitória (3ª) e derrota (1ª), sem textos; ficam o escudo, a moldura e o botão (com a lupa)
    def row(y0, y1, name):
        r = a[y0:y1, 64:1798].copy()
        h, w = r.shape[:2]
        for (x0, x1) in [(120, 420), (425, 760), (830, 1140), (1560 - 64 + 60, 1720 - 64 + 50)]:
            pass
        def clr(bx0, bx1, thr=58):
            nonlocal r
            m = np.zeros((h, w), np.uint8)
            sub = r[8:h - 8, bx0:bx1]
            sat = sub.max(axis=2).astype(int) - sub.min(axis=2).astype(int)
            m[8:h - 8, bx0:bx1] = (((lum(sub) > thr) | (sat > 70))).astype(np.uint8) * 255
            m = cv2.dilate(m, np.ones((5, 5), np.uint8))
            m[:6] = 0; m[h - 6:] = 0
            r = inpaint(r, m, 5)
        clr(118, 412)            # DERROTA / RANQUEADA
        clr(426, 1160)           # ícone do modo, vs, data, peão, lances
        clr(1560 - 64, 1720 - 64 + 10, 70)   # texto ANALISAR (a lupa fica: x < 1552)
        save_rgba(np.dstack([r, np.full((h, w), 255, np.uint8)]), name)
    row(224, 309, 'hist_row_loss')
    row(408, 496, 'hist_row_win')
    save_rgba(cut_icon(a, (900, 236, 950, 296)), 'ico_peao_branco')
    save_rgba(cut_icon(a, (900, 424, 950, 486), thr=30), 'ico_peao_preto')
    print('historico ok')

# ======================================================================= CONHEÇA O FRAIHA
ABOUT_NAV = [(204, 268), (279, 342), (352, 417), (427, 491), (502, 567), (577, 643)]

def build_conheca():
    a = load('conheca')
    out = a.copy()
    src = clean_block(a, (610, 660, 1300, 740), 40, 12)
    def fill(box):
        x0, y0, x1, y1 = src
        tile = a[y0:y1, x0:x1]
        th, tw = tile.shape[:2]
        bx0, by0, bx1, by1 = box
        for y in range(by0, by1):
            for x in range(bx0, bx1, tw):
                ww = min(tw, bx1 - x)
                out[y, x:x + ww] = tile[(y - by0) % th, :ww]
    # menu da esquerda: os 6 tópicos saem (o jogo desenha molduras, ícones e o escolhido)
    fill((116, 198, 596, 650))
    # ícone grande e textos do tópico saem (o castelo pintado fica)
    big = cut_icon(a, (660, 222, 776, 332), thr=60)
    save_rgba(big, 'about_ico_projeto_big')
    m = np.zeros(a.shape[:2], np.uint8)
    sub = a[222:334, 660:776]
    m[222:334, 660:776] = ((lum(sub) > 60) | ((sub.max(axis=2) - sub.min(axis=2).astype(int)) > 70)).astype(np.uint8) * 255
    m = cv2.dilate(m, np.ones((5, 5), np.uint8))
    out = inpaint(out, m, 6)
    out = clear_light(out, (800, 226, 1250, 306), thr=70, grow=3, r=6)
    out = clear_light(out, (650, 360, 1580, 668), thr=78, grow=3, r=6)
    save(out, 'about_bg')
    # moldura dos tópicos: comum (COMO JOGAR) e escolhido (O PROJETO), sem ícone/texto
    tc = strip_inner(a[277:345, 120:592].copy(), 12, 12)
    save_rgba(np.dstack([tc, np.full(tc.shape[:2], 255, np.uint8)]), 'about_btn')
    ts = strip_inner(a[200:272, 116:596].copy(), 14, 12)
    save_rgba(np.dstack([ts, np.full(ts.shape[:2], 255, np.uint8)]), 'about_btn_sel')
    for i, (name, box) in enumerate([('about_ico_projeto', (152, 208, 210, 264)), ('about_ico_como', (150, 284, 210, 338)),
                                     ('about_ico_ligas', (150, 358, 210, 412)), ('about_ico_modos', (150, 432, 210, 488)),
                                     ('about_ico_perso', (150, 508, 210, 562)), ('about_ico_comunidade', (150, 584, 212, 640))]):
        save_rgba(cut_icon(a, box), name)
    print('conheca ok')

# ======================================================================= CONFIGURAÇÕES
def build_config():
    a = load('config')
    out = a.copy()
    # textos vivos saem: MÚSICA · 22%, EFEITOS SONOROS · 28%, PRÉ-MOVE: LIGADO / Jogue na vez…, versão
    out = clear_light(out, (186, 492, 520, 532), thr=80, grow=3, r=6)
    out = clear_light(out, (186, 608, 600, 650), thr=80, grow=3, r=6)
    out = clear_light(out, (300, 808, 1100, 902), thr=80, grow=3, r=6)
    out = clear_light(out, (975, 1038, 1290, 1074), thr=70, grow=2, r=5)
    # trilhos dos sliders: o preenchimento dourado e o botão (esmeralda) saem; o trilho vazio fica (o jogo desenha)
    def track(y0, y1, empty_x):
        t = a[y0:y1, empty_x:empty_x + 1]
        for x in range(206, 1236):
            out[y0:y1, x:x + 1] = t
    track(540, 572, 600)
    track(658, 692, 600)
    # devolve os losangos do trilho (estão em x ~665, 838, 1134)
    for (y0, y1) in [(540, 572), (658, 692)]:
        for cx in [665, 838, 1134]:
            out[y0:y1, cx - 8:cx + 9] = a[y0:y1, cx - 8:cx + 9]
    # o botão esmeralda saía para fora do trilho (em cima e embaixo): limpa com o fundo do painel
    for (x0, y0, x1, y1) in [(418, 522, 488, 541), (418, 571, 488, 590), (476, 640, 544, 659), (476, 691, 544, 710)]:
        out[y0:y1, x0:x1] = a[y0:y1, x0 + 140:x1 + 140]   # mesmo trecho do painel, 140 px à direita
    save(out, 'config_bg')
    # peças do slider: preenchimento (faixa dourada) e o botão esmeralda
    fill = a[543:569, 216:226].copy()
    save_rgba(np.dstack([fill, np.full(fill.shape[:2], 255, np.uint8)]), 'slider_fill')
    knob = a[531:582, 426:478].copy()
    l = lum(knob); sat = knob.max(axis=2).astype(int) - knob.min(axis=2).astype(int)
    al = np.where((l > 40) | (sat > 50), 255, 0).astype(np.uint8)
    save_rgba(np.dstack([knob, al]), 'slider_knob')
    print('config ok')

# ======================================================================= PERFIL DO JOGADOR
PIECE_DARK = [None]
def build_perfil():
    a = load('perfil')
    out = a.copy()
    src = clean_block(a, (200, 345, 680, 375), 30, 8)
    def fill(box):
        x0, y0, x1, y1 = src
        tile = a[y0:y1, x0:x1]
        th, tw = tile.shape[:2]
        bx0, by0, bx1, by1 = box
        for y in range(by0, by1):
            for x in range(bx0, bx1, tw):
                ww = min(tw, bx1 - x)
                out[y, x:x + ww] = tile[(y - by0) % th, :ww]
    fill((20, 74, 1212, 368))      # miolo inteiro (abas, galeria, detalhe, nome, botões) sai
    out = clear_light(out, (300, 56, 520, 74), thr=60, grow=2, r=4)   # "7 de 19 avatares conquistados"
    save(out, 'perfil_bg')
    sx0, sy0, sx1, sy1 = src
    dark = a[sy0:sy1, sx0:sx1].reshape(-1, 3).mean(axis=0)
    PIECE_DARK[0] = dark
    def piece(box, name, strip=False, pad=(10, 8)):
        nonlocal_dark = dark
        x0, y0, x1, y1 = box
        c = a[y0:y1, x0:x1].copy()
        if strip:
            # miolo liso (cor do painel): o jogo desenha o conteúdo; ficam só a moldura e os cantos
            h, w = c.shape[:2]
            px, py = pad
            inner = c[py:h - py, px:w - px]
            lum_in = lum(inner)
            keep = np.zeros(lum_in.shape, bool)
            c[py:h - py, px:w - px] = np.where(keep[..., None], inner, PIECE_DARK[0])
        save_rgba(np.dstack([c, np.full(c.shape[:2], 255, np.uint8)]), name)
    green = a[90:96, 170:182].reshape(-1, 3).mean(axis=0)
    dark_saved = dark
    PIECE_DARK[0] = green
    piece((26, 80, 191, 131), 'pf_tab_sel', True, (6, 6))
    PIECE_DARK[0] = dark_saved
    piece((26, 151, 191, 202), 'pf_tab', True, (6, 6))
    save_rgba(cut_icon(a, (44, 88, 76, 122)), 'pf_ico_avatares')
    save_rgba(cut_icon(a, (42, 158, 78, 196), thr=50), 'pf_ico_icones')
    piece((206, 70, 324, 204), 'pf_card_sel', True, (9, 9))
    piece((332, 81, 435, 201), 'pf_card', True, (7, 7))
    piece((564, 209, 666, 338), 'pf_card_locked', True, (7, 7))
    piece((706, 65, 1202, 201), 'pf_detail', True, (8, 8))
    piece((717, 231, 1193, 269), 'pf_field', True, (4, 4))
    piece((692, 321, 843, 363), 'pf_btn_alterar')
    piece((857, 321, 1009, 363), 'pf_btn_remover')
    piece((1021, 321, 1194, 363), 'pf_btn_personalizar')
    piece((1037, 156, 1187, 192), 'pf_btn_dim', True, (6, 6))
    print('perfil ok')

if __name__ == '__main__':
    build_bots()
    build_ligas()
    build_historico()
    build_conheca()
    build_config()
    build_perfil()
