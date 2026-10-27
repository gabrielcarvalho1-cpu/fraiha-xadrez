# R198 · RANKING (PC) com a ARTE do dono: painel limpo + abas (acesa/apagada, sem texto), ícones das abas,
# linhas do 1º/2º/3º (com o louro e o número) e a linha comum, anel do retrato e ícones de liga.
# Uso: python3 tools/art/ranking_r198.py <referencia.png>
import sys, numpy as np
from PIL import Image, ImageFilter
src = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).astype(np.float32)
OUT = "ui_kit/pages/ranking_r198/"
def wipe(a, x0, y0, x1, y1, cx, w=4):
    a[y0:y1, x0:x1] = a[y0:y1, cx:cx + w].mean(axis=1, keepdims=True)
def lerp_wipe(a, x0, y0, x1, y1, lx, rx, w=3):
    # apaga com a mistura (linha a linha) entre uma coluna limpa à esquerda e outra à direita: mantém o degradê
    L = a[y0:y1, lx:lx + w].mean(axis=1, keepdims=True)
    R = a[y0:y1, rx:rx + w].mean(axis=1, keepdims=True)
    t = np.linspace(0, 1, x1 - x0)[None, :, None]
    a[y0:y1, x0:x1] = L * (1 - t) + R * t
def save(a, name):
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(OUT + name, optimize=True)
    print(name, a.shape[1], a.shape[0])
def icon(box, mode, ref=None, thr=60):
    x0, y0, x1, y1 = box
    a = src[y0:y1, x0:x1].copy()
    rgb = a[..., :3]
    lum = rgb.mean(axis=2)
    if mode == "light":   m = np.clip((lum - 95) / 50, 0, 1)
    elif mode == "dark":  m = np.clip((110 - lum) / 50, 0, 1)
    else:
        # cavalo: o fundo é o que está ligado à borda e parece a placa limpa (o contorno escuro do cavalo separa)
        from scipy import ndimage
        diff = np.abs(rgb - ref[y0:y1, x0:x1, :3]).sum(axis=2)
        near = (diff < thr) | (a[..., 3] < 30)
        lab, n = ndimage.label(near)
        edge = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
        bgm = np.isin(lab, [e for e in edge if e != 0])
        m = 1.0 - ndimage.binary_dilation(bgm, iterations=0 or 1).astype(np.float32) * 0.0 - bgm.astype(np.float32)
    mi = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    a[..., 3] = np.minimum(a[..., 3], np.asarray(mi).astype(np.float32))
    return a
# --- painel: sem as linhas (o jogo põe) e sem o texto SUA POSIÇÃO
p = src.copy()
band = p[326:331, 1000:1004].mean(axis=(0, 1))
p[328:592, 96:2078] = np.array([12, 22, 44, 255], np.float32)
wipe(p, 138, 604, 860, 678, 132)
save(p, "painel.png")
# --- abas dos modos: a apagada é a do XEQUE limpa; a acesa é a mesma placa com o miolo azul trocado pelo dourado
# do XADREZ (linha por linha), mantendo a moldura e os losangos
off = src[14:162, 786:1378].copy(); wipe(off, 30, 40, 560, 132, 1000 - 786); save(off, "mode_off.png")
gold = src[14:162, 365:369].mean(axis=1)            # perfil dourado (linha a linha) do miolo do XADREZ
on = off.copy()
rgb = on[..., :3]
navy = (rgb[..., 2] > rgb[..., 0] + 8) & (rgb.mean(axis=2) < 110) & (on[..., 3] > 200)
navy[:30] = False; navy[136:] = False
for y in range(on.shape[0]):
    on[y, navy[y], :3] = gold[y, :3]
save(on, "mode_on.png")
save(icon((850, 50, 962, 150), "light"), "ico_xeque.png")
save(icon((1440, 44, 1572, 146), "light"), "ico_marcha.png")
# --- abas do xadrez (ritmos)
c_on = src[162:262, 84:596].copy(); wipe(c_on, 26, 18, 486, 84, 262 - 84); save(c_on, "chess_on.png")
c_off = src[162:262, 598:1090].copy(); wipe(c_off, 24, 18, 470, 84, 818 - 598); save(c_off, "chess_off.png")
save(icon((195, 180, 258, 248), "dark"), "ico_relampago.png")
save(icon((728, 178, 812, 248), "light"), "ico_rapida.png")
save(icon((1203, 178, 1268, 248), "light"), "ico_normal.png")
save(icon((1672, 178, 1742, 248), "light"), "ico_convencional.png")
# --- linhas (o degradê de cada linha é refeito da esquerda para a direita)
for i, (y0, y1) in enumerate([(328, 416), (413, 501), (498, 590)]):
    r = src[y0:y1, 88:2088].copy(); lerp_wipe(r, 240 - 88, 0, 2052 - 88, y1 - y0, 236 - 88, 2054 - 88); save(r, "row%d.png" % (i + 1))
r = src[413:501, 88:2088].copy(); lerp_wipe(r, 12, 0, 2052 - 88, 88, 12 - 6, 2054 - 88); save(r, "row.png")
ring = src[414:500, 256:354].copy()
yy, xx = np.mgrid[0:ring.shape[0], 0:ring.shape[1]]
d = np.hypot(xx - 48.5, yy - 42.5)
ring[..., 3] = np.where((d < 33.5) | (d > 44.0), 0, ring[..., 3])
save(ring, "ring.png")
def hexa(a):
    h, w = a.shape[:2]
    m = Image.new("L", (w * 4, h * 4), 0)
    from PIL import ImageDraw
    cx, cy, R = w * 2, h * 2, min(w, h) * 2 - 6
    import math
    ImageDraw.Draw(m).polygon([(cx + R * math.cos(math.radians(90 + 60 * j)), cy + R * math.sin(math.radians(90 + 60 * j))) for j in range(6)], fill=255)
    m = np.asarray(m.resize((w, h), Image.LANCZOS)).astype(np.float32)
    a[..., 3] = np.minimum(a[..., 3], m)
    return a
save(hexa(src[336:410, 1218:1290].copy()), "liga_madeira.png")
save(hexa(src[506:580, 1218:1290].copy()), "liga_ferro.png")
# --- cavalo do XADREZ: recorte automático (GrabCut) do cavalo dourado de cima da placa dourada
import cv2
x0, y0, x1, y1 = 200, 10, 350, 152
crop = np.asarray(Image.open(sys.argv[1]).convert("RGBA"))[y0:y1, x0:x1].copy()
bgr = cv2.cvtColor(crop[..., :3], cv2.COLOR_RGB2BGR)
mask = np.zeros(bgr.shape[:2], np.uint8); bm = np.zeros((1, 65)); fm = np.zeros((1, 65))
cv2.grabCut(bgr, mask, (12, 4, 128, 134), bm, fm, 8, cv2.GC_INIT_WITH_RECT)
m = cv2.GaussianBlur(np.where((mask == 1) | (mask == 3), 255, 0).astype(np.uint8), (3, 3), 0)
crop[..., 3] = np.minimum(crop[..., 3], m)
Image.fromarray(crop).save(OUT + "ico_xadrez.png")
print("ico_xadrez.png")
# ======== R198b · ABAS feitas da própria arte, no lugar exato (sem placa recortada por cima):
# cada aba é copiada da referência no mesmo retângulo (texto apagado com o degradê do miolo); a versão do outro
# estado troca SÓ o miolo (achado por "balde de tinta" a partir do centro, bordas suaves) pelo degradê dourado ou
# azul da arte. Ícones dos ritmos saem da placa e entram por cima (claro na aba azul, escuro na dourada).
import cv2
REF = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).astype(np.float32)
def profile(x, y0, y1, w=3):
    return np.median(REF[y0:y1, x:x + w], axis=1)      # (h, 4)
GOLD_M = profile(655, 30, 150, 90); NAVY_M = profile(1300, 30, 150)
GOLD_C = profile(470, 168, 256, 50); NAVY_C = profile(1300, 168, 256)
def fill_mask(a, seed, tol=7):
    bgr = cv2.cvtColor(a[..., :3].astype(np.uint8), cv2.COLOR_RGB2BGR)
    m = np.zeros((a.shape[0] + 2, a.shape[1] + 2), np.uint8)
    cv2.floodFill(bgr, m, seed, (0, 0, 0), (tol, tol, tol), (tol, tol, tol), 4 | cv2.FLOODFILL_MASK_ONLY | (255 << 8))
    m = m[1:-1, 1:-1].astype(np.float32) / 255.0
    m = cv2.dilate(m, np.ones((2, 2), np.uint8))
    return cv2.GaussianBlur(m, (3, 3), 0.8)
def paint(a, m, prof):
    ys = np.where(m.max(axis=1) > 0.5)[0]
    y0, y1 = ys.min(), ys.max() + 1
    idx = np.clip(((np.arange(a.shape[0]) - y0) / max(1, y1 - y0) * len(prof)).astype(int), 0, len(prof) - 1)
    tgt = prof[idx][:, None, :3]
    a[..., :3] = a[..., :3] * (1 - m[..., None]) + tgt * m[..., None]
    return a
def bevel_gold(a, m):
    ring = cv2.dilate((m > 0.3).astype(np.uint8), np.ones((9, 9), np.uint8)).astype(bool) & ~(m > 0.3)
    rgb = a[..., :3]
    blue = ring & (rgb[..., 2] > rgb[..., 0] + 10)
    lum = rgb.mean(axis=2, keepdims=True) / 140.0
    gold = np.clip(np.array([90, 55, 8]) + lum * np.array([200, 150, 40]), 0, 255)
    a[..., :3] = np.where(blue[..., None], gold, rgb)
    return a
def bevel_navy(a, m):
    ring = cv2.dilate((m > 0.3).astype(np.uint8), np.ones((9, 9), np.uint8)).astype(bool) & ~(m > 0.3)
    rgb = a[..., :3]
    warm = ring & (rgb[..., 0] > rgb[..., 2] + 30) & (rgb.mean(axis=2) < 150)
    lum = rgb.mean(axis=2, keepdims=True) / 140.0
    navy = np.clip(np.array([4, 18, 40]) + lum * np.array([20, 50, 90]), 0, 255)
    a[..., :3] = np.where(warm[..., None], navy, rgb)
    return a
def tab(rect, wipes, seed, gold_now, prof_gold, prof_navy, name):
    x0, y0, x1, y1 = rect
    a = REF[y0:y1, x0:x1].copy()
    for w in wipes:
        if len(w) == 5:
            (wx0, wy0, wx1, wy1, cx) = w
            a[wy0 - y0:wy1 - y0, wx0 - x0:wx1 - x0] = a[wy0 - y0:wy1 - y0, cx - x0:cx - x0 + 3].mean(axis=1, keepdims=True)
        else:   # (x0, y0, x1, y1, coluna limpa à esquerda, coluna limpa à direita): degradê entre as duas
            (wx0, wy0, wx1, wy1, lx, rx) = w
            L = a[wy0 - y0:wy1 - y0, lx - x0:lx - x0 + 3].mean(axis=1, keepdims=True)
            R = a[wy0 - y0:wy1 - y0, rx - x0:rx - x0 + 3].mean(axis=1, keepdims=True)
            t = np.linspace(0, 1, wx1 - wx0)[None, :, None]
            a[wy0 - y0:wy1 - y0, wx0 - x0:wx1 - x0] = L * (1 - t) + R * t
    m = fill_mask(a, (seed[0] - x0, seed[1] - y0), 10 if gold_now else 6)
    same = a.copy()
    other = paint(a.copy(), m, prof_navy if gold_now else prof_gold)
    other = bevel_navy(other, m) if gold_now else bevel_gold(other, m)   # R198d · o chanfro de dentro acompanha a cor
    save(same, name + ("_on.png" if gold_now else "_off.png"))
    save(other, name + ("_off.png" if gold_now else "_on.png"))
# modos (XADREZ dourada na arte; o cavalo, as espadas e a coroa ficam na placa)
tab((150, 14, 790, 162), [(395, 58, 655, 135, 385, 690)], (700, 100), True, GOLD_M, NAVY_M, "tab_xadrez")
tab((765, 14, 1400, 162), [(1035, 58, 1240, 135, 1020, 1255)], (1150, 100), False, GOLD_M, NAVY_M, "tab_xeque")
tab((1370, 14, 2030, 162), [(1578, 58, 1972, 135, 1568, 1980)], (1770, 100), False, GOLD_M, NAVY_M, "tab_marcha")
# ritmos (RELÂMPAGO dourada); os ícones saem
tab((84, 160, 596, 262), [(190, 176, 520, 250, 540)], (540, 212), True, GOLD_C, NAVY_C, "tab_ranked_3min")
tab((590, 160, 1090, 262), [(720, 176, 1000, 250, 1030)], (1030, 212), False, GOLD_C, NAVY_C, "tab_ranked_5min")
tab((1082, 160, 1590, 262), [(1195, 176, 1450, 250, 1480)], (1480, 212), False, GOLD_C, NAVY_C, "tab_ranked_10min")
tab((1578, 160, 2085, 262), [(1665, 176, 2000, 250, 2020)], (2020, 212), False, GOLD_C, NAVY_C, "tab_ranked_20min")
# ícones dos ritmos nas duas cores
for n in ["relampago", "rapida", "normal", "convencional"]:
    ic = np.asarray(Image.open(OUT + "ico_%s.png" % n).convert("RGBA")).astype(np.float32)
    dark = ic.copy(); dark[..., :3] = [38, 22, 6]
    light = ic.copy(); light[..., :3] = [230, 232, 236]
    save(dark, "ico_%s_on.png" % n); save(light, "ico_%s_off.png" % n)
# ícones dos modos recortados por GrabCut (com o contorno escuro; o recorte por luz deixava as espadas e a coroa lavadas)
def grab(box, rect_in, name):
    x0, y0, x1, y1 = box
    crop = np.asarray(Image.open(sys.argv[1]).convert("RGBA"))[y0:y1, x0:x1].copy()
    bgr = cv2.cvtColor(crop[..., :3], cv2.COLOR_RGB2BGR)
    mask = np.zeros(bgr.shape[:2], np.uint8); bm = np.zeros((1, 65)); fm = np.zeros((1, 65))
    cv2.grabCut(bgr, mask, rect_in, bm, fm, 8, cv2.GC_INIT_WITH_RECT)
    m = cv2.GaussianBlur(np.where((mask == 1) | (mask == 3), 255, 0).astype(np.uint8), (3, 3), 0)
    crop[..., 3] = np.minimum(crop[..., 3], m)
    Image.fromarray(crop).save(OUT + name)
grab((845, 46, 968, 154), (4, 2, 115, 104), "ico_xeque.png")
grab((1436, 40, 1576, 150), (6, 4, 126, 102), "ico_marcha.png")
# ======== R198e · a aba do outro estado = a PLACA VERDADEIRA da arte (XADREZ dourada / XEQUE azul; RELÂMPAGO
# dourada / RÁPIDA azul, já sem texto): ponta direita igual, ponta esquerda espelhada e o meio esticado na largura.
def load_np(n): return np.asarray(Image.open(OUT + n).convert("RGBA")).astype(np.float32)
def build(src, right_x, mid_x0, width):
    right = src[:, right_x:]
    left = right[:, ::-1]
    mid = src[:, mid_x0:right_x]
    mw = width - 2 * right.shape[1]
    mid = cv2.resize(mid, (mw, src.shape[0]), interpolation=cv2.INTER_LINEAR)
    return np.concatenate([left, mid, right], axis=1)
def put(base, icon_file, at):
    ic = load_np(icon_file); x, y = at; h, w = ic.shape[:2]
    a = ic[..., 3:4] / 255.0
    base[y:y + h, x:x + w, :3] = base[y:y + h, x:x + w, :3] * (1 - a) + ic[..., :3] * a
    base[y:y + h, x:x + w, 3:4] = np.maximum(base[y:y + h, x:x + w, 3:4], ic[..., 3:4])
    return base
GOLD = load_np("tab_xadrez_on.png")          # 640 de largura, x0 = 150
NAVY = load_np("tab_xeque_off.png")          # 635, x0 = 765
save(put(build(GOLD, 640 - 150, 360 - 150, 635), "ico_xeque.png", (845 - 765, 46 - 14)), "tab_xeque_on.png")
save(put(build(GOLD, 640 - 150, 360 - 150, 660), "ico_marcha.png", (1436 - 1370, 40 - 14)), "tab_marcha_on.png")
save(put(build(NAVY, 1250 - 765, 990 - 765, 640), "ico_xadrez.png", (200 - 150, 0)), "tab_xadrez_off.png")
CG = load_np("tab_ranked_3min_on.png")       # 512, x0 = 84
CN = load_np("tab_ranked_5min_off.png")      # 500, x0 = 590
for bid, w in [("ranked_5min", 500), ("ranked_10min", 508), ("ranked_20min", 507)]:
    save(build(CG, 470 - 84, 150 - 84, w), "tab_%s_on.png" % bid)
save(build(CN, 960 - 590, 650 - 590, 512), "tab_ranked_3min_off.png")
