#!/usr/bin/env python3
"""R66 · MARCHA REAL (PC): Pátios e peões no estilo da referência nova do dono (tools/ui_ref/r66/marcha_tabuleiro_ref.png).

O traçado do tabuleiro (Muralha, Salão, Portões) continua o da arte R57 — as casas medidas continuam valendo.
Muda só o que a referência redesenhou:
  • PÁTIO: losango com grade 2x2 (4 casas quadradas) e flores-de-lis nas pontas, recortado da referência,
    sem os peões (o miolo de cada casa é refeito a partir da borda da própria casa) e colado no lugar do losango
    antigo de cada reino. Os 4 círculos de silhueta (que a referência não tem) saem da mesa.
  • PEÃO: o jogo usa a arte em alta dos peões (marcha/art/pawns), que já é o peão da referência (R67).
  • board_layout_r57.gd: HOMES / HOME_CENTERS passam a ser as 4 casas da grade de cada Pátio.
Entradas: tools/ui_ref/r66/marcha_tabuleiro_ref.png, marcha/art/r57/mesa.png (versão R57, sem Pátio novo).
Saídas: marcha/art/r57/mesa.png, mesa_wide.png (via tools/marcha_wide_r65.py) e HOMES em marcha/board_layout_r57.gd.
Uso: python3 tools/marcha_board_r66.py   (roda sobre a mesa R57 guardada em tools/ui_ref/r66/mesa_r57.png)
"""
import os
import re
import subprocess
import sys

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
REF = os.path.join(ROOT, "tools/ui_ref/r66/marcha_tabuleiro_ref.png")
MESA_R57 = os.path.join(ROOT, "tools/ui_ref/r66/mesa_r57.png")      # mesa antes do R66 (fonte fixa)
BOARD_CROP = (480, 110, 1210, 745)
BOARD_F = 1600.0 / (BOARD_CROP[2] - BOARD_CROP[0])
SEATS = ["marfim", "rubi", "onix", "esmeralda"]

# Pátios na referência (px 847x834): pontas do losango (esq, cima, dir, baixo) e retângulo da grade 2x2 (dentro do filete)
REF_BASES = {
    "rubi": {"tips": (88, 96, 272, 268), "grid": (120, 130, 240, 240)},
    "onix": {"tips": (532, 62, 718, 240), "grid": (568, 96, 684, 206)},
    "marfim": {"tips": (115, 502, 320, 700), "grid": (156, 541, 281, 662)},
    "esmeralda": {"tips": (557, 462, 767, 660), "grid": (600, 501, 726, 622)},
}
# Pátio antigo de cada reino na mesa R57 (centro em px do recorte do tabuleiro) — mesmo lugar do novo
HOMES_R57 = {"marfim": (217.5, 517.0), "rubi": (136.0, 173.5), "onix": (525.0, 115.0), "esmeralda": (597.5, 460.0)}
NEW_SIZE = (146, 134)        # largura x altura do Pátio novo na mesa (px do recorte do tabuleiro)
OLD_DIAMOND = (74, 67)       # meia largura / meia altura do losango antigo (com a borda)
SILHOUETTES = [(603.0, 186.6, 47), (210.6, 99.0, 45), (505.8, 528.6, 44), (137.4, 445.8, 46)]


def load(p):
    return np.array(Image.open(p).convert("RGB"))


def cells(grid):
    x0, y0, x1, y1 = grid
    mx, my = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    return [((x0, y0, mx, my)), ((mx, y0, x1, my)), ((x0, my, mx, y1)), ((mx, my, x1, y1))]


def coons(a, x0, y0, x1, y1):
    """Miolo da casa refeito só a partir das 4 bordas dele (interpolação de Coons): degradê liso, sem manchas."""
    f = a.astype(np.float32)
    T, B = f[y0, x0:x1 + 1], f[y1, x0:x1 + 1]
    L, R = f[y0:y1 + 1, x0], f[y0:y1 + 1, x1]
    h, w = y1 - y0 + 1, x1 - x0 + 1
    u = np.linspace(0, 1, w)[None, :, None]
    v = np.linspace(0, 1, h)[:, None, None]
    P = (1 - u) * L[:, None, :] + u * R[:, None, :] + (1 - v) * T[None, :, :] + v * B[None, :, :] \
        - ((1 - u) * (1 - v) * f[y0, x0] + u * (1 - v) * f[y0, x1] + (1 - u) * v * f[y1, x0] + u * v * f[y1, x1])
    a[y0:y1 + 1, x0:x1 + 1] = np.clip(P + 0.5, 0, 255).astype(np.uint8)


PAD = 7


def smooth_cell(a, x0, y0, x1, y1, outer):
    """Miolo liso da casa: cor dos cantos de dentro (onde o peão não chega) em degradê bilinear, com o centro
    um pouco mais claro (o brilho da casa da referência). O canto `outer` (0 TL, 1 TR, 2 BL, 3 BR) é cortado
    pela borda do losango: a cor dele vem dos outros três (plano)."""
    f = a.astype(np.float32)
    k = 5
    tl = f[y0:y0 + k, x0:x0 + k].reshape(-1, 3).mean(0)
    tr = f[y0:y0 + k, x1 - k + 1:x1 + 1].reshape(-1, 3).mean(0)
    bl = f[y1 - k + 1:y1 + 1, x0:x0 + k].reshape(-1, 3).mean(0)
    br = f[y1 - k + 1:y1 + 1, x1 - k + 1:x1 + 1].reshape(-1, 3).mean(0)
    if outer == 0: tl = tr + bl - br
    elif outer == 1: tr = tl + br - bl
    elif outer == 2: bl = tl + br - tr
    else: br = tr + bl - tl
    h, w = y1 - y0 + 1, x1 - x0 + 1
    u = np.linspace(0, 1, w)[None, :, None]
    v = np.linspace(0, 1, h)[:, None, None]
    P = (1 - u) * (1 - v) * tl + u * (1 - v) * tr + (1 - u) * v * bl + u * v * br
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    yy, xx = np.mgrid[0:h, 0:w]
    rr = np.sqrt(((xx - cx) / (w / 2.0)) ** 2 + ((yy - cy) / (h / 2.0)) ** 2)
    P = P * (1.0 + 0.10 * np.clip(1.0 - rr, 0, 1))[..., None]
    # o canto de fora (borda do losango) fica como está na arte
    keep = np.zeros((h, w), bool)
    lim = 0.20 * (w + h)
    if outer == 0: keep = (xx + yy) < lim
    elif outer == 1: keep = ((w - 1 - xx) + yy) < lim
    elif outer == 2: keep = (xx + (h - 1 - yy)) < lim
    else: keep = ((w - 1 - xx) + (h - 1 - yy)) < lim
    region = a[y0:y1 + 1, x0:x1 + 1]
    out = np.clip(P + 0.5, 0, 255).astype(np.uint8)
    out[keep] = region[keep]
    a[y0:y1 + 1, x0:x1 + 1] = out


def clean_base(ref, spec):
    """Recorte do Pátio sem os peões: o miolo de cada casa é refeito a partir dos cantos dela."""
    a = ref.copy()
    m = np.zeros(a.shape[:2], np.uint8)
    for i, (x0, y0, x1, y1) in enumerate(cells(spec["grid"])):
        bx0, by0, bx1, by1 = int(x0 + PAD), int(y0 + PAD), int(x1 - PAD), int(y1 - PAD)
        smooth_cell(a, bx0, by0, bx1, by1, i)
        m[by0:by1 + 1, bx0:bx1 + 1] = 255
    return a, m


def stone_patch(a, cx, cy, r, src_img):
    """Tampa um círculo com pedra limpa: procura na referência (na escala da mesa) o pedaço sem ouro/contas cujo
    anel em volta mais combina com o anel em volta do buraco e cola com borda suave."""
    hsv = cv2.cvtColor(src_img, cv2.COLOR_RGB2HSV)
    busy = ((hsv[..., 1] > 110) & (hsv[..., 2] > 110)) | (hsv[..., 2] > 190)
    R = r + 8
    yy, xx = np.mgrid[-R:R + 1, -R:R + 1]
    dist = np.sqrt(xx ** 2 + yy ** 2)
    ring = (dist > r) & (dist <= R)
    tgt = a[cy - R:cy + R + 1, cx - R:cx + R + 1].astype(np.float32)
    best = None
    H, W = busy.shape
    integ = cv2.integral(busy.astype(np.uint8))
    for sy in range(R + 2, H - R - 2, 2):
        for sx in range(R + 2, W - R - 2, 2):
            y0, y1, x0, x1 = sy - R, sy + R + 1, sx - R, sx + R + 1
            if integ[y1, x1] - integ[y0, x1] - integ[y1, x0] + integ[y0, x0] > 0: continue
            src = src_img[y0:y1, x0:x1].astype(np.float32)
            e = float(((src - tgt)[ring] ** 2).mean())
            if best is None or e < best[0]: best = (e, sx, sy)
    _, sx, sy = best
    src = src_img[sy - R:sy + R + 1, sx - R:sx + R + 1].astype(np.float32)
    al = np.clip((R - dist) / 6.0, 0, 1)[..., None]
    a[cy - R:cy + R + 1, cx - R:cx + R + 1] = np.clip(tgt * (1 - al) + src * al + 0.5, 0, 255).astype(np.uint8)


# Portão de cada reino (centro) e a conta vizinha da trilha (modelo da conta), px do recorte do tabuleiro
GATES = [((309.4, 604.2), (309.3, 576.7)), ((45.0, 255.5), (79.1, 257.7)), ((425.0, 38.4), (423.0, 63.7)), ((684.0, 372.5), (652.0, 373.6))]
GATE_TINT = [None, (205, 28, 44), (38, 40, 52), (24, 150, 86)]       # Marfim fica com a conta clara (só o aro)
YOU_PANEL = (1306, 784, 1656, 908)                                   # painel "Você" (px da mesa 1672x941)


def gate_bead(a, c, src, tint, r=15):
    """Copia a conta vizinha (mesma luz e sombra da trilha) para o Portão, tinge na cor do reino mantendo o brilho
    e põe um aro dourado fino, macio."""
    cx, cy = int(round(c[0])), int(round(c[1]))
    sx, sy = int(round(src[0])), int(round(src[1]))
    R = r + 3
    yy, xx = np.mgrid[-R:R + 1, -R:R + 1].astype(np.float32)
    d = np.sqrt(xx ** 2 + yy ** 2)
    patch = a[sy - R:sy + R + 1, sx - R:sx + R + 1].astype(np.float32)
    tgt = a[cy - R:cy + R + 1, cx - R:cx + R + 1].astype(np.float32)
    if tint is not None:
        L = patch.mean(axis=2, keepdims=True) / 255.0
        col = np.array(tint, np.float32)
        tinted = col * np.clip(L * 1.08, 0, 1.15) + (255 - col) * np.clip((L - 0.9) / 0.1, 0, 1) ** 2 * 0.6
        inb = np.clip((r - 2.0 - d) / 1.5, 0, 1)[..., None]
        patch = patch * (1 - inb) + tinted * inb
    al = np.clip((R - d) / 2.5, 0, 1)[..., None]
    out = tgt * (1 - al) + patch * al
    ring = np.clip(1.0 - np.abs(d - (r - 0.5)) / 1.1, 0, 1)[..., None] * 0.9
    out = out * (1 - ring) + np.array([238, 196, 70], np.float32) * ring
    a[cy - R:cy + R + 1, cx - R:cx + R + 1] = np.clip(out + 0.5, 0, 255).astype(np.uint8)


def remove_panel(a, box):
    """Tira o painel: o tapete de baixo continua para cima ao longo da diagonal das listras (amostrando uma faixa de
    linhas limpas, não uma só, para manter a textura) e o canto ganha a sombra do salão; emenda suave."""
    x0, y0, x1, y1 = box
    H, W = a.shape[:2]
    b0, b1 = y1 + 4, H - 2               # faixa limpa abaixo do painel
    vx, vy = 1.0, 0.55                   # direção das listras do tapete
    f = a.astype(np.float32)
    out = f.copy()
    band = b1 - b0
    for y in range(y0 - 8, y1 + 6):
        for x in range(x0 - 10, x1 + 10):
            ph = ((y - b0) % band + band) % band
            acc = 0.0
            col = np.zeros(3, np.float32)
            for k, w in ((0, 1.0 - ph / band), (1, ph / band)):    # duas amostras: a emenda entre faixas some
                sy = b0 + ph - k * band if k else b0 + ph
                if sy < b0: sy += band
                sy = min(sy, b1 - 1)
                sx = x + (sy - y) / vy * vx
                while sx > W - 1: sx -= 2 * band / vy * vx
                col += f[int(sy), int(np.clip(round(sx), 0, W - 1))] * (0.5 + 0.5 * w)
                acc += 0.5 + 0.5 * w
            out[y, x] = col / acc
    m = np.zeros((H, W), np.float32)
    m[y0 - 2:y1 + 2, x0 - 4:x1 + 4] = 1.0
    m = cv2.GaussianBlur(m, (0, 0), 3.5)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    shade = 0.62 + 0.38 * np.clip((yy - y0) / (y1 - y0 + 30.0), 0, 1)      # mais escuro em cima (sombra das colunas)
    res = f * (1 - m[..., None]) + out * (shade * m)[..., None]
    return np.clip(res + 0.5, 0, 255).astype(np.uint8)


def diamond_alpha(w, h, feather=1.5):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.abs(xx - (w - 1) / 2.0) / (w / 2.0) + np.abs(yy - (h - 1) / 2.0) / (h / 2.0)
    return np.clip((1.0 - d) * (min(w, h) / 2.0) / feather, 0, 1)


def main():
    ref = load(REF)
    mesa = load(MESA_R57)
    ox, oy = BOARD_CROP[0], BOARD_CROP[1]
    # 0) R69 · Portões: a conta pintada (parecia adesivo) vira a conta de verdade da trilha, tingida na cor do reino
    for seat, (g, nb) in enumerate(GATES):
        gate_bead(mesa, (g[0] + ox, g[1] + oy), (nb[0] + ox, nb[1] + oy), GATE_TINT[seat])
    # 0b) R69 · sai o painel "Você" do canto de baixo à direita (cenário refeito por textura)
    mesa = remove_panel(mesa, YOU_PANEL)
    # 1) losangos antigos e círculos de silhueta saem da mesa (recomposição a partir da pedra em volta)
    hole = np.zeros(mesa.shape[:2], np.uint8)
    for (cx, cy) in HOMES_R57.values():
        hw, hh = OLD_DIAMOND
        pts = np.array([[cx + ox, cy + oy - hh], [cx + ox + hw, cy + oy], [cx + ox, cy + oy + hh], [cx + ox - hw, cy + oy]], np.int32)
        cv2.fillConvexPoly(hole, pts, 255)
    for (cx, cy, r) in SILHOUETTES:
        cv2.circle(hole, (int(round(cx + ox)), int(round(cy + oy))), r + 6, 255, -1)
    avoid = cv2.dilate(hole, np.ones((9, 9), np.uint8))
    mesa = cv2.inpaint(mesa, hole, 7, cv2.INPAINT_TELEA)
    k = (BOARD_CROP[2] - BOARD_CROP[0]) / float(ref.shape[1])
    ref_small = cv2.resize(ref, (int(ref.shape[1] * k), int(ref.shape[0] * k)), interpolation=cv2.INTER_AREA)
    for (cx, cy, r) in SILHOUETTES:
        stone_patch(mesa, int(round(cx + ox)), int(round(cy + oy)), r, ref_small)
    # 2) Pátios novos (recorte da referência, sem peões) + peões novos
    homes_units, centers_units = {}, {}
    for name, spec in REF_BASES.items():
        clean, _ = clean_base(ref, spec)
        l, t, r, b = spec["tips"]
        crop = clean[t:b + 1, l:r + 1]
        W, H = NEW_SIZE
        small = cv2.resize(crop, (W, H), interpolation=cv2.INTER_AREA)
        al = diamond_alpha(W, H)[..., None]
        cx, cy = HOMES_R57[name]
        x0, y0 = int(round(cx + ox - W / 2.0)), int(round(cy + oy - H / 2.0))
        tgt = mesa[y0:y0 + H, x0:x0 + W].astype(np.float32)
        mesa[y0:y0 + H, x0:x0 + W] = np.clip(tgt * (1 - al) + small.astype(np.float32) * al + 0.5, 0, 255).astype(np.uint8)
        # casas da grade → coordenadas do tabuleiro (unidades 1600)
        sx, sy = W / (r - l + 1.0), H / (b - t + 1.0)
        pts = []
        for (gx0, gy0, gx1, gy1) in cells(spec["grid"]):
            px = x0 - ox + ((gx0 + gx1) / 2.0 - l) * sx
            py = y0 - oy + ((gy0 + gy1) / 2.0 - t) * sy
            half = (gy1 - gy0) / 2.0 * sy
            pts.append((round(px * BOARD_F, 1), round((py + half * 0.62) * BOARD_F - 11.0, 1)))   # pé do peão perto do fundo da casa
        gx = (spec["grid"][0] + spec["grid"][2]) / 2.0
        gy = (spec["grid"][1] + spec["grid"][3]) / 2.0
        homes_units[name] = pts
        centers_units[name] = (round((x0 - ox + (gx - l) * sx) * BOARD_F, 1), round((y0 - oy + (gy - t) * sy) * BOARD_F, 1))
    Image.fromarray(mesa).save(os.path.join(ROOT, "marcha/art/r57/mesa.png"), optimize=True)
    # 3) layout: HOMES / HOME_CENTERS das grades novas (ordem dos assentos: Marfim, Rubi, Ônix, Esmeralda)
    v = lambda p: "Vector2(%.1f, %.1f)" % p
    lay = os.path.join(ROOT, "marcha/board_layout_r57.gd")
    s = open(lay, encoding="utf-8").read()
    homes = "const HOMES := [" + ", ".join("[" + ", ".join(v(p) for p in homes_units[n]) + "]" for n in SEATS) + "]"
    cents = "const HOME_CENTERS := [" + ", ".join(v(centers_units[n]) for n in SEATS) + "]"
    s = re.sub(r"^const HOMES := .*$", "## R66 · Pátio em grade 2x2 (tools/marcha_board_r66.py)\n" + homes if "R66" not in s else homes, s, count=1, flags=re.M)
    s = re.sub(r"^const HOME_CENTERS := .*$", cents, s, count=1, flags=re.M)
    open(lay, "w", encoding="utf-8", newline="\n").write(s)
    # 4) laterais da mesa larga (R65) a partir da mesa nova
    subprocess.run([sys.executable, os.path.join(ROOT, "tools/marcha_wide_r65.py"), ROOT], check=True)
    print("OK R66")


if __name__ == "__main__":
    main()
