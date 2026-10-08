#!/usr/bin/env python3
"""R53 · Telas do CELULAR no visual das referências aprovadas (tools/ui_ref/mobile/mob_*.jpg, 900 x 1600).
O painel da referência vira peças empilháveis (faixas na largura inteira de 900 px): o fundo preto da
referência fica transparente (o cenário do FRAIHA aparece em volta), o que é vivo (títulos de tópico,
textos, números) é apagado da arte e o jogo desenha por cima. Faixas "tile" são linhas sem texto do miolo,
repetidas para o painel crescer com o conteúdo. Saída: ui_kit/mobile/*.png
Uso: python3 tools/mobile_ref_pages.py"""
import os, sys
import numpy as np
import cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, 'tools', 'ui_ref', 'mobile')
OUT = os.path.join(ROOT, 'ui_kit', 'mobile')
os.makedirs(OUT, exist_ok=True)

def load(n):
    return np.array(Image.open(os.path.join(REF, n + '.jpg')).convert('RGB')).astype(np.float64)

def key_alpha(a, thr=9):
    """Fundo preto ligado à borda da imagem -> transparente (o contorno escuro da moldura fica)."""
    h, w = a.shape[:2]
    dark = (a.max(axis=2) < thr).astype(np.uint8)
    lab = cv2.connectedComponents(dark, connectivity=4)[1]
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border)) & (dark == 1)
    al = np.where(bg, 0.0, 255.0)
    # borda suave de 1 px (sem halo preto duro sobre o cenário)
    al = cv2.GaussianBlur(al, (3, 3), 0.8)
    al[~bg] = 255.0
    return al

def save(rgb, al, n, y0, y1, colors=0):
    piece = np.dstack([np.clip(rgb[y0:y1], 0, 255), np.clip(al[y0:y1], 0, 255)]).astype(np.uint8)
    img = Image.fromarray(piece, 'RGBA')
    if colors:
        img = img.quantize(colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert('RGBA')
    img.save(os.path.join(OUT, n + '.png'), optimize=True)
    print(n, img.size)

def ink(a, box, thr=95, grow=2):
    """Só o traço claro (ouro/creme) de uma caixa, com alpha: ornamentos que vão por cima do miolo."""
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    l = sub.mean(axis=2)
    m = (l > thr).astype(np.uint8)
    m = cv2.dilate(m, np.ones((grow * 2 + 1, grow * 2 + 1), np.uint8))
    al = cv2.GaussianBlur(m.astype(np.float64) * 255.0, (3, 3), 0.8)
    return np.dstack([np.clip(sub, 0, 255), al]).astype(np.uint8)

def donor_fill(a, box, rows):
    """Troca a caixa pelas linhas lisas do próprio miolo (mesmas colunas: o padrão fraco continua alinhado)."""
    x0, y0, x1, y1 = box
    r0, r1 = rows
    out = a.copy()
    k = r1 - r0
    don = a[r0:r1, x0:x1]
    def tone(rows):   # tom médio por coluna só do fundo escuro (sem ouro nem texto)
        m = (rows.mean(axis=2) < 55).astype(np.float64)
        num = cv2.blur((rows * m[..., None]).sum(axis=0), (121, 1))
        den = cv2.blur(m.sum(axis=0)[:, None], (121, 1))
        return num / np.maximum(den, 1e-3) + 1.0
    dm = tone(don)
    top = tone(a[y0 - 8:y0 - 1, x0:x1])
    bot = tone(a[y1 + 1:y1 + 8, x0:x1])
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0 - 1)
        gain = np.clip((top * (1 - t) + bot * t) / dm, 0.8, 1.4)   # acompanha o degradê do entorno
        out[y, x0:x1] = a[r0 + (y - y0) % k, x0:x1] * gain
    # costura suave nas bordas verticais da caixa
    for d in range(1, 4):
        w = d / 4.0
        out[y0:y1, x0 - 1 + d] = a[y0:y1, x0 - 1 + d] * (1 - w) + out[y0:y1, x0 - 1 + d] * w
        out[y0:y1, x1 - d] = a[y0:y1, x1 - d] * (1 - w) + out[y0:y1, x1 - d] * w
    return out

def save_rgba(piece, n):
    Image.fromarray(piece, 'RGBA').save(os.path.join(OUT, n + '.png'), optimize=True)
    print(n, piece.shape[1], piece.shape[0])

# ---------------------------------------------------------------- MAIS (ref3): arte inteira, textos fixos
def build_mais():
    a = load('mob_mais')
    al = key_alpha(a)
    save(a, al, 'mais_panel', 30, 1510)

# ---------------------------------------------------------------- CONHEÇA (ref4)
# topo (cabeçalho, VOLTAR, começo do cartão com a linha de título) · linha lisa do miolo · fim do cartão
ABOUT_TOP = (40, 962)
ABOUT_TILE = (1122, 1160)
ABOUT_END = (1272, 1460)
def build_conheca():
    a = load('mob_conheca')
    al = key_alpha(a)
    row = ink(a, (130, 750, 776, 870))          # flor-de-lis + divisória (sem o título)
    t = row.copy()
    t[10:92, 92:424, 3] = 0                     # "O PROJETO" fora (x 222..554)
    save_rgba(t, 'about_title_row')
    b = donor_fill(a, (214, 756, 566, 846), ABOUT_TILE)     # título do tópico (vivo)
    b = donor_fill(b, (114, 892, 788, 962), ABOUT_TILE)     # 1ª linha do texto (vivo)
    save(b, al, 'about_top', *ABOUT_TOP)
    save(a, al, 'about_tile', *ABOUT_TILE)
    save(a, al, 'about_end', *ABOUT_END)

# ---------------------------------------------------------------- HISTÓRICO (ref2)
HIST_TOP = (5, 734)
HIST_TILE = (704, 734)
HIST_END = (1080, 1560)
def build_historico():
    a = load('mob_historico')
    al = key_alpha(a)
    save(a, al, 'hist_top', *HIST_TOP)
    save(a, al, 'hist_tile', *HIST_TILE)
    save(a, al, 'hist_end', *HIST_END)

# ---------------------------------------------------------------- LIGAS E RANKING (ref7)
# topo (cabeçalho, VOLTAR, faixa do jogador) · uma faixa por liga (as laterais de madeira/folhas são as da
# própria referência) · miolo da linha em 3 estados (escolhida / disponível / bloqueada) sem brasão e sem nome
# (o jogo desenha o brasão oficial da liga e o nome) · fim. Linhas de 104 px a partir de y 621 (Bronze).
LIGA_TOP = (0, 404)
LIGA_END = (1449, 1598)
LIGA_ROW_H = 104
def liga_row_y(i):          # linha i da referência (0 Madeira … 9 Grande Mestre); 0/1 usam a do Ferro (104 px)
    return 517 if i < 2 else 621 + (i - 2) * LIGA_ROW_H
def colcopy(a, box, src_x):
    """Miolo de faixa horizontal: repete a coluna limpa src_x por toda a caixa (bordas e degradê vertical ficam)."""
    x0, y0, x1, y1 = box
    out = a.copy()
    out[y0:y1, x0:x1] = a[y0:y1, src_x:src_x + 1]
    return out
def build_ligas():
    a = load('mob_ligas')
    al = key_alpha(a)
    b = colcopy(a, (262, 330, 712, 398), 258)               # "Gabriel — Madeira · 0 / 100 PL" (vivo)
    save(b, al, 'ligas_top', *LIGA_TOP)
    for i in range(10):
        y = liga_row_y(i)
        save(a, al, 'ligas_row%d' % i, y, y + LIGA_ROW_H)
    # miolo: x 86..792; brasão (x 112..270) e nome (x 270..505) apagados repetindo a coluna 272
    for n, (y0, y1) in [('sel', (404, 517)), ('on', (517, 621)), ('off', (621, 725))]:
        c = colcopy(a, (114, y0, 272, y1), 274)
        c = colcopy(c, (272, y0, 508 if n != 'off' else 512, y1), 274)
        mid = np.dstack([np.clip(c[y0:y1, 86:792], 0, 255), np.full((y1 - y0, 706), 255.0)]).astype(np.uint8)
        save_rgba(mid, 'ligas_mid_' + n)
    # louros verdes atrás do brasão (só o verde das folhas, do brasão do Bronze)
    y = liga_row_y(2)
    sub = a[y:y + LIGA_ROW_H, 112:272]
    r, g, bl = sub[..., 0], sub[..., 1], sub[..., 2]
    m = ((g > r + 12) & (g > bl + 8) & (g > 45)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    alm = cv2.GaussianBlur(m.astype(np.float64) * 255.0, (3, 3), 0.7)
    save_rgba(np.dstack([np.clip(sub, 0, 255), alm]).astype(np.uint8), 'ligas_laurel')
    save(a, al, 'ligas_end', *LIGA_END)

# ---------------------------------------------------------------- JOGAR CONTRA O COMPUTADOR (ref6)
# topo (cabeçalho, VOLTAR, aviso fixo) · cartão de bot (o do Ferro, sem brasão, textos, selo e botão) repetido
# para os 11 bots · fim (com o 2º VOLTAR). O botão sai como peça com transparência
# (o jogo escurece o bloqueado) e os textos, o selo de estado e os brasões são do jogo.
BOT_TOP = (0, 400)
BOT_CARD = (735, 1081)
BOT_END = (1424, 1598)
def shape_alpha(c, thr=36):
    """Alpha de uma peça (botão/selo) recortada sobre o fundo escuro: em cada linha, do 1º ao último pixel
    mais claro que o fundo (contorno) fica opaco — o miolo escuro da peça entra junto."""
    m = (c.mean(axis=2) > thr).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    if n > 2: m = (lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))).astype(np.uint8)   # só a peça
    out = np.zeros_like(m)
    for y in range(m.shape[0]):
        xs = np.where(m[y])[0]
        if xs.size: out[y, xs[0]:xs[-1] + 1] = 1
    return cv2.GaussianBlur(out.astype(np.float64) * 255.0, (3, 3), 0.8)
def build_bots():
    from ref_pages_v2 import fill_smooth
    a = load('mob_bots')
    al = key_alpha(a)
    save(a, al, 'bots_top', *BOT_TOP)
    save(a, al, 'bots_end', *BOT_END)
    # peças do cartão do Ferro (antes de apagar)
    btn = a[978:1064, 276:794].copy()
    btn = colcopy(np.pad(btn, ((0, 0), (0, 0), (0, 0))), (152, 8, 452, 78), 460)    # texto fora (ícone fica)
    save_rgba(np.dstack([np.clip(btn, 0, 255), shape_alpha(btn, 40)]).astype(np.uint8), 'bots_button')
    crown = a[934:972, 326:368].copy()
    save_rgba(np.dstack([np.clip(crown, 0, 255), shape_alpha(crown, 70)]).astype(np.uint8), 'bots_crown')
    sub = a[840:965, 108:312]
    r, g, bl = sub[..., 0], sub[..., 1], sub[..., 2]
    m = ((g > r + 12) & (g > bl + 8) & (g > 45)).astype(np.uint8)
    alm = cv2.GaussianBlur(m.astype(np.float64) * 255.0, (3, 3), 0.7)
    save_rgba(np.dstack([np.clip(sub, 0, 255), alm]).astype(np.uint8), 'bots_laurel')
    c = a.copy()
    c = fill_smooth(c, (101, 751, 801, 1067), ring=6, thr=60, green=True, sigma=40)   # miolo inteiro: degradê liso
    save(c, al, 'bots_card', *BOT_CARD)

# ---------------------------------------------------------------- JOGAR RANQUEADO (ref8)
# topo (cavalos, título e aviso fixos) · cartão do ritmo (o do Relâmpago, sem brasão e sem os textos vivos;
# a moldura da barra de PL e o BUSCAR PARTIDA ficam) repetido para os ritmos abertos · fim (VOLTAR).
RK_TOP = (0, 545)
RK_CARD = (545, 959)
RK_END = (1354, 1594)
def build_ranqueado():
    from ref_pages_v2 import fill_smooth
    a = load('mob_ranqueado')
    al = key_alpha(a)
    save(a, al, 'rk_top', *RK_TOP)
    save(a, al, 'rk_end', *RK_END)
    c = fill_smooth(a, (136, 560, 774, 725), ring=6, thr=60, green=True, sigma=30)   # brasão, nome, minutos, liga
    c = fill_smooth(c, (150, 768, 772, 816), ring=6, thr=60, green=True, sigma=20)   # V · D · E · partidas
    save(c, al, 'rk_card', *RK_CARD)

if __name__ == '__main__':
    only = sys.argv[1:]
    for name, fn in [('mais', build_mais), ('conheca', build_conheca), ('historico', build_historico), ('ligas', build_ligas), ('bots', build_bots), ('ranqueado', build_ranqueado)]:
        if not only or name in only: fn()
