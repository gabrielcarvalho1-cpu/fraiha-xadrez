#!/usr/bin/env python3
"""R51 · Kit visual do FRAIHA tirado das imagens de referência do dono (tools/ui_ref/*.png).
Recorta molduras de botão/caixa/placa (9-slice: cantos e bordas originais, miolo com uma coluna limpa
repetida, sem texto) e ícones (fundo removido). Saída: ui_kit/art/*.png. Rodar: python3 tools/ui_kit_build.py
"""
import os, sys
from collections import deque
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, 'tools', 'ui_ref')
OUT = os.path.join(ROOT, 'ui_kit', 'art')
os.makedirs(OUT, exist_ok=True)
_cache = {}
def ref(name):
    if name not in _cache: _cache[name] = Image.open(os.path.join(REF, name + '.png')).convert('RGBA')
    return _cache[name]

def dist(a, b): return sum(abs(int(x) - int(y)) for x, y in zip(a[:3], b[:3]))

def key_outside(im, tol=60, dark=90):
    """Torna transparente o fundo escuro que encosta na borda do recorte (fora da moldura)."""
    im = im.copy(); px = im.load(); w, h = im.size
    seen = set(); q = deque()
    for x in range(w): q.extend([(x, 0), (x, h - 1)])
    for y in range(h): q.extend([(0, y), (w - 1, y)])
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h): continue
        seen.add((x, y)); p = px[x, y]
        if max(p[:3]) > dark: continue
        px[x, y] = (0, 0, 0, 0)
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return im

def key_color(im, bg, tol=70):
    """Ícone: tira a cor de fundo (miolo do botão) conectada à borda."""
    im = im.copy(); px = im.load(); w, h = im.size
    seen = set(); q = deque()
    for x in range(w): q.extend([(x, 0), (x, h - 1)])
    for y in range(h): q.extend([(0, y), (w - 1, y)])
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h): continue
        seen.add((x, y)); p = px[x, y]
        if dist(p, bg) > tol: continue
        px[x, y] = (0, 0, 0, 0)
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return im

def nine(src, box, left, right, clean_x, mid=24, outside=True, name=None, dark=90):
    """Moldura 9-slice: [left px originais][mid colunas = coluna limpa repetida][right px originais]."""
    x0, y0, x1, y1 = box
    im = ref(src).crop(box)
    w, h = im.size
    out = Image.new('RGBA', (left + mid + right, h))
    out.paste(im.crop((0, 0, left, h)), (0, 0))
    col = im.crop((clean_x - x0, 0, clean_x - x0 + 1, h))
    for i in range(mid): out.paste(col, (left + i, 0))
    out.paste(im.crop((w - right, 0, w, h)), (left + mid, 0))
    if outside: out = key_outside(out, dark=dark)
    if name: out.save(os.path.join(OUT, name + '.png'))
    return out

def icon(src, box, bg_at=None, tol=70, name=None):
    im = ref(src).crop(box)
    bg = im.getpixel(bg_at) if bg_at else im.getpixel((1, 1))
    out = key_color(im, bg, tol)
    bb = out.getbbox()
    if bb: out = out.crop(bb)
    if name: out.save(os.path.join(OUT, name + '.png'))
    return out

def strip(src, box, name):
    im = ref(src).crop(box); im.save(os.path.join(OUT, name + '.png')); return im


def frame(src, box, l, r, t, b, cx, cy, inner, mid=24, name=None, dark=40):
    """Moldura de PAINEL 9-slice: 4 cantos originais (l/r/t/b px), bordas = coluna cx / linha cy limpas repetidas,
    miolo = o pixel (cx, cy) repetido. Fora da moldura vira transparente."""
    x0, y0, x1, y1 = box
    im = ref(src).crop(box); w, h = im.size
    W, H = l + mid + r, t + mid + b
    out = Image.new('RGBA', (W, H))
    for (sx0, sx1, dx) in [(0, l, 0), (w - r, w, l + mid)]:
        for (sy0, sy1, dy) in [(0, t, 0), (h - b, h, t + mid)]:
            out.paste(im.crop((sx0, sy0, sx1, sy1)), (dx, dy))
    colx = cx - x0; rowy = cy - y0
    top = im.crop((colx, 0, colx + 1, t)); bot = im.crop((colx, h - b, colx + 1, h))
    lef = im.crop((0, rowy, l, rowy + 1)); rig = im.crop((w - r, rowy, w, rowy + 1))
    cen = im.crop((colx, rowy, colx + 1, rowy + 1))
    for i in range(mid):
        out.paste(top, (l + i, 0)); out.paste(bot, (l + i, t + mid))
        out.paste(lef, (0, t + i)); out.paste(rig, (l + mid, t + i))
        for j in range(mid): out.paste(cen, (l + i, t + j))
    # transparente só FORA do retângulo da moldura (inner = l,t,r,b da borda) e só onde é fundo escuro
    il, it, ir, ib = inner
    ir = W - (w - ir); ib = H - (h - ib)
    keyed = key_outside(out, dark=dark)
    px = out.load(); kp = keyed.load()
    for y in range(H):
        for x in range(W):
            if not (il <= x < ir and it <= y < ib): px[x, y] = kp[x, y]
    if name: out.save(os.path.join(OUT, name + '.png'))
    return out

# ---------------- AMIGOS ----------------
A = 'amigos'
nine(A, (1263, 185, 1507, 283), 40, 40, 1311, name='btn_verde')          # BUSCAR / CONVIDAR
nine(A, (770, 386, 1124, 482), 34, 40, 870, name='btn_azul')               # MENSAGEM
nine(A, (97, 50, 377, 137), 28, 44, 172, name='btn_vermelho', dark=40)              # VOLTAR (ponta à direita)
nine(A, (452, 20, 1133, 165), 170, 170, 640, name='placa_titulo', dark=50)   # placa AMIGOS
nine(A, (86, 372, 1509, 499), 18, 18, 600, outside=False, name='caixa_linha')      # linha do amigo
nine(A, (88, 600, 1496, 698), 56, 56, 300, outside=False, name='caixa_vazia')      # "Ninguém por aqui."
nine(A, (88, 186, 1244, 284), 26, 26, 1000, outside=False, name='campo')           # campo de busca
icon(A, (1190, 400, 1256, 463), name='ico_espadas')
icon(A, (800, 404, 862, 462), name='ico_balao')
icon(A, (126, 72, 162, 124), name='ico_voltar', tol=60)
icon(A, (116, 206, 176, 266), name='ico_lupa')
icon(A, (86, 312, 132, 358), name='ico_sec_online', tol=50)
icon(A, (86, 538, 134, 588), name='ico_sec_partida', tol=50)
icon(A, (86, 733, 132, 780), name='ico_sec_offline', tol=50)
strip(A, (600, 338, 1504, 353), 'sec_linha')                           # linha dourada com o losango no fim
frame(A, (0, 0, 1576, 975), 90, 230, 178, 75, 1200, 720, (30, 30, 1559, 952), name='painel_amigos')
icon(A, (760, 925, 822, 975), name='orn_base', tol=40)                  # losango da base da moldura
print('kit ok ->', OUT)
