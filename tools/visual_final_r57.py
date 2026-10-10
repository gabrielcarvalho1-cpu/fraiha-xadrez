#!/usr/bin/env python3
"""R57 · ATUALIZAÇÃO VISUAL FINAL (XEQUE + MARCHA REAL) a partir das 4 referências finais do dono.

As referências são a ESPECIFICAÇÃO: cada tela usa a própria imagem de referência como "placa" de fundo e
apaga SÓ o que é dinâmico (nomes, textos de resultado, avatares, peões, cartas, timer...). O jogo desenha
esses dados ao vivo exatamente nos mesmos lugares (xeque/xeque_view.gd · _draw_result_r57,
marcha/marcha_ui.gd · desk_*).

Entradas (tools/ui_ref/r57/):
  xeque_derrota.png   1672x941   (referência 1)
  xeque_vitoria.png   1672x941   (referência 2)
  marcha_partida.png  1672x941   (referência 3)
  marcha_lobby.png    1494x834   (referência 4)
Saídas: ver main().
Uso: python3 tools/visual_final_r57.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
REF = os.path.join(ROOT, "tools/ui_ref/r57")


def load(name):
    return np.array(Image.open(os.path.join(REF, name)).convert("RGB"))


def save(arr, rel, rgba=False):
    out = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    Image.fromarray(arr, "RGBA" if rgba else "RGB").save(out, optimize=True)
    return out


def hsv(a):
    return cv2.cvtColor(a, cv2.COLOR_RGB2HSV)


def text_mask(a, box, kind):
    """Máscara dos pixels de TEXTO dentro de box (x0,y0,x1,y1), conforme o tipo de fundo."""
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1].astype(np.int32)
    h = hsv(a[y0:y1, x0:x1].astype(np.uint8)).astype(np.int32)
    v, s = h[..., 2], h[..., 1]
    r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
    if kind == "light":          # texto claro (creme/branco/dourado) sobre fundo escuro
        m = v > 105
    elif kind == "banner":       # texto creme sobre faixa vermelha
        m = (s < 110) & (v > 150)
    elif kind == "diff":         # tudo que destoa do fundo liso da linha (texto + antisserrilhado)
        med = np.median(sub.reshape(-1, 3), axis=0)
        m = np.abs(sub - med).sum(axis=2) > 46
    elif kind == "tag":          # selo azul "BOT" (caixa inteira)
        m = (b > r + 35) & (b > 120)
    else:
        raise ValueError(kind)
    full = np.zeros(a.shape[:2], np.uint8)
    full[y0:y1, x0:x1] = m.astype(np.uint8) * 255
    return full


def fill_box(mask, box):
    x0, y0, x1, y1 = box
    mask[y0:y1, x0:x1] = 255
    return mask


def inpaint(a, mask, grow=2, radius=5):
    if grow:
        mask = cv2.dilate(mask, np.ones((2 * grow + 1, 2 * grow + 1), np.uint8))
    return cv2.inpaint(a, mask, radius, cv2.INPAINT_TELEA)


# ------------------------------------------------------------------ XEQUE · resultado
XQ = {
    # áreas em px da referência 1672x941 (iguais na derrota e na vitória)
    "portrait": (351, 281, 645, 550),          # imagem dentro da moldura grande (vencedor)
    "name": (365, 578, 632, 640),              # "Torre Velha" na plaquinha
    "place": (322, 650, 668, 694),             # "VOCÊ FICOU EM 4º LUGAR"
    "banner": (898, 276, 1432, 324),           # "XEQUE-MATE FINAL EM DAMA DE FERRO"
    "rows_y": [370, 462, 553, 645],            # topo de cada linha (avatar)
    "row_text": (940, 0, 1268, 74),            # (x0, dy0, x1, dy1) relativo ao topo da linha
    "row_avatar": (859, 2, 929, 72),           # (x0, dy0, x1, dy1)
}
JEWELS = [(478, 262, 518, 300), (478, 532, 518, 572), (330, 395, 372, 437), (624, 395, 666, 437)]


def xeque_plate(src, out_rel, jewel_rel):
    a = load(src)
    m = np.zeros(a.shape[:2], np.uint8)
    m |= text_mask(a, XQ["name"], "light")
    m |= text_mask(a, XQ["place"], "light")
    m |= text_mask(a, XQ["banner"], "banner")
    x0, dy0, x1, dy1 = XQ["row_text"]
    for y in XQ["rows_y"]:
        box = (x0, y + dy0, x1, y + dy1)
        tag = text_mask(a, box, "tag")
        ys, xs = np.nonzero(tag)
        if len(xs):
            fill_box(tag, (xs.min() - 3, ys.min() - 3, xs.max() + 4, ys.max() + 4))
        m |= tag
        m |= text_mask(a, box, "light")
        m |= text_mask(a, box, "diff")
    clean = inpaint(a, m)
    # retratos: o jogo desenha por cima (a moldura das joias vem da camada de joias)
    save(clean, out_rel)
    # joias da moldura grande que invadem a imagem do retrato: camada com alfa (dourado/vermelho)
    j = np.zeros((a.shape[0], a.shape[1], 4), np.uint8)
    pr = XQ["portrait"]
    for (jx0, jy0, jx1, jy1) in JEWELS:
        sub = a[jy0:jy1, jx0:jx1].astype(np.int32)
        r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
        gold = (r > 120) & (r > b + 45) & (g > 60)
        red = (r > 110) & (g < 70) & (b < 80)
        blue = (b > r + 40) & (b > 100)          # joias azuis da vitória
        keep = (gold | red | blue).astype(np.uint8)
        keep = cv2.dilate(keep, np.ones((3, 3), np.uint8))           # contorno escuro junto
        # fora da área do retrato a placa já tem a joia: só importa a parte DENTRO do retrato
        yy, xx = np.mgrid[jy0:jy1, jx0:jx1]
        inside = (xx >= pr[0]) & (xx < pr[2]) & (yy >= pr[1]) & (yy < pr[3])
        alpha = (keep * inside * 255).astype(np.uint8)
        j[jy0:jy1, jx0:jx1, :3] = a[jy0:jy1, jx0:jx1]
        j[jy0:jy1, jx0:jx1, 3] = np.maximum(j[jy0:jy1, jx0:jx1, 3], alpha)
    # recorta só a moldura grande (economiza textura)
    fx0, fy0, fx1, fy1 = 320, 250, 680, 585
    save(j[fy0:fy1, fx0:fx1], jewel_rel, rgba=True)


# ------------------------------------------------------------------ MARCHA REAL · partida (referência 3)
# Tabuleiro da referência: recorte (480,110)-(1210,745) da imagem 1672x941. As casas foram medidas na própria
# arte (contas brancas) e seguem a MESMA topologia do jogo (marcha/board_layout.gd): 76 casas na Muralha
# (19 por reino), 4 no Salão do Trono e 4 no Pátio de cada reino. Saída: marcha/board_layout_r57.gd.
BOARD_CROP = (480, 110, 1210, 745)
BOARD_W = 1600.0                              # largura do tabuleiro em "unidades do tabuleiro" (como o 1600 do jogo)
BOARD_F = BOARD_W / (BOARD_CROP[2] - BOARD_CROP[0])
# braço do Marfim (19 casas, sentido horário a partir do Portão) + os outros 3, em px do recorte
ARMS = [
    # Marfim (embaixo): Portão no canto esquerdo da fileira de baixo, sobe a coluna, diagonal, fileira, sobe 3
    [(309.4, 604.2), (309.3, 576.7), (308.9, 549.7), (308.9, 523.1), (309.1, 496.5), (308.7, 468.9),
     (285.9, 449.4), (264.8, 431.1), (243.8, 411.5), (222.8, 392.5),
     (199.7, 373.7), (169.5, 373.7), (139.2, 373.5), (109.4, 373.7), (78.9, 373.4), (44.7, 373.8),
     (44.7, 344.1), (45.1, 315.0), (44.8, 287.2)],
    # Rubi (esquerda)
    [(45.0, 255.5), (79.1, 257.7), (109.3, 257.8), (139.3, 257.7), (169.2, 257.7), (199.5, 257.8),
     (222.8, 240.1), (244.1, 221.7), (265.1, 202.0), (286.1, 183.7),
     (308.9, 168.5), (309.0, 142.1), (309.2, 116.2), (309.0, 90.4), (309.0, 63.3), (309.4, 36.7),
     (340.3, 36.8), (369.5, 37.1), (397.8, 36.7)],
    # Ônix (em cima)
    [(425.0, 38.4), (423.0, 63.7), (422.9, 90.7), (423.0, 116.6), (422.9, 142.3), (423.7, 168.5),
     (446.7, 183.9), (467.6, 202.2), (488.7, 221.5), (510.2, 240.3),
     (532.7, 258.0), (562.6, 257.7), (592.5, 257.6), (622.8, 258.0), (652.5, 257.7), (683.2, 257.6),
     (683.0, 287.1), (683.2, 315.3), (683.3, 344.3)],
    # Esmeralda (direita)
    [(684.0, 372.5), (652.0, 373.6), (622.7, 373.7), (592.9, 373.3), (562.4, 373.8), (532.5, 373.6),
     (510.0, 392.5), (488.5, 411.4), (467.7, 431.0), (445.8, 449.4),
     (423.4, 468.6), (422.9, 496.5), (422.9, 522.9), (423.0, 549.4), (423.0, 576.6), (422.5, 606.0),
     (396.3, 604.4), (367.8, 604.5), (339.6, 604.5)],
]
# Salão do Trono (da entrada para o fundo) e centro do Pátio de cada reino
LANES = [
    [(366.0, 563.2), (366.0, 537.9), (366.0, 512.6), (366.0, 487.4)],
    [(80.0, 316.0), (110.0, 316.0), (140.0, 316.0), (170.0, 316.0)],
    [(365.5, 70.4), (365.5, 96.1), (365.5, 122.0), (365.5, 147.5)],
    [(650.0, 316.0), (620.0, 316.0), (590.0, 316.0), (560.0, 316.0)],
]
# Pátios: o losango do Marfim fica embaixo à esquerda (junto do Portão dele) e o do Rubi em cima à esquerda —
# na arte enviada as cores desses dois losangos estavam trocadas; a placa troca os dois de lugar.
HOMES = [(217.5, 517.0), (136.0, 173.5), (525.0, 115.0), (597.5, 460.0)]
HOME_OFF = [(0, -27), (-30, -4), (30, -4), (0, 20)]
GATE_COLORS = [(250, 244, 228), (200, 22, 40), (30, 33, 40), (26, 154, 90)]


def board_pt(p):
    return (round(p[0] * BOARD_F, 1), round(p[1] * BOARD_F, 1))


def write_layout():
    track = [board_pt(p) for arm in ARMS for p in arm]
    assert len(track) == 76
    lanes = [[board_pt(p) for p in ln] for ln in LANES]
    homes = [[board_pt((c[0] + o[0], c[1] + o[1])) for o in HOME_OFF] for c in HOMES]
    centers = [board_pt(c) for c in HOMES]
    h = (BOARD_CROP[3] - BOARD_CROP[1]) * BOARD_F
    v = lambda p: "Vector2(%.1f, %.1f)" % p
    lines = [
        "extends RefCounted",
        "## R57 · MARCHA REAL no PC: casas medidas na arte final do dono (tools/ui_ref/r57/marcha_partida.png).",
        "## GERADO por tools/visual_final_r57.py — não editar à mão. Mesma API e mesma topologia de board_layout.gd",
        "## (76 casas na Muralha, 19 por reino; 4 no Salão e 4 no Pátio de cada reino; sentido horário).",
        "## Coordenadas em unidades do tabuleiro: largura %.0f (o recorte da arte tem %d x %d px)." % (BOARD_W, BOARD_CROP[2] - BOARD_CROP[0], BOARD_CROP[3] - BOARD_CROP[1]),
        "const SIZE := %.1f" % BOARD_W,
        "const HEIGHT := %.1f" % h,
        "const TRACK_LEN := 76",
        "const ARM := 19",
        "const CELL_RADIUS := 18.0",
        "const CENTER := %s" % v(board_pt((365.0, 318.0))),
        "## recorte da arte (px da referência 1672x941) que corresponde ao tabuleiro",
        "const ART_RECT := Rect2(%d, %d, %d, %d)" % (BOARD_CROP[0], BOARD_CROP[1], BOARD_CROP[2] - BOARD_CROP[0], BOARD_CROP[3] - BOARD_CROP[1]),
        "const TRACK := [" + ", ".join(v(p) for p in track) + "]",
        "const LANES := [" + ", ".join("[" + ", ".join(v(p) for p in ln) + "]" for ln in lanes) + "]",
        "const HOMES := [" + ", ".join("[" + ", ".join(v(p) for p in hm) + "]" for hm in homes) + "]",
        "const HOME_CENTERS := [" + ", ".join(v(p) for p in centers) + "]",
        "",
        "static func track_cell(abs_index: int) -> Vector2:",
        "    return TRACK[posmod(abs_index, TRACK_LEN)]",
        "",
        "static func lane_cell(seat: int, k: int) -> Vector2:",
        "    return LANES[posmod(seat, 4)][clampi(k, 0, 3)]",
        "",
        "static func home_cell(seat: int, slot: int) -> Vector2:",
        "    return HOMES[posmod(seat, 4)][slot % 4]",
        "",
        "static func home_center(seat: int) -> Vector2:",
        "    return HOME_CENTERS[posmod(seat, 4)]",
        "",
        "static func gate_index(seat: int) -> int:",
        "    return seat * ARM",
        "",
        "static func entrance_index(seat: int) -> int:",
        "    return posmod(seat * ARM - 2, TRACK_LEN)",
        "",
    ]
    with open(os.path.join(ROOT, "marcha/board_layout_r57.gd"), "w", newline="\n") as f:
        f.write("\n".join(lines))


def sphere(a, cx, cy, col, r=11.0, ring=True):
    """conta brilhante (Portão) desenhada sobre a placa, com aro dourado como o Portão preto da arte."""
    H, W = a.shape[:2]
    x0, x1, y0, y1 = int(cx - 16), int(cx + 17), int(cy - 16), int(cy + 17)
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = (xx + 0.5 - cx) / r, (yy + 0.5 - cy) / r
    d = np.sqrt(dx * dx + dy * dy)
    sub = a[y0:y1, x0:x1].astype(np.float32)
    if ring:
        rr = d * r
        ringm = np.clip(1.0 - np.abs(rr - 12.6) / 1.3, 0, 1)[..., None]
        sub = sub * (1 - ringm) + np.array([246, 205, 40], np.float32) * ringm
        gap = np.clip(1.0 - np.abs(rr - 11.4) / 0.9, 0, 1)[..., None] * 0.85
        sub = sub * (1 - gap) + np.array([8, 6, 4], np.float32) * gap
    inside = np.clip((1.0 - d) * r, 0, 1)[..., None]
    z = np.sqrt(np.clip(1 - d * d, 0, 1))
    L = np.array([-0.45, -0.55, 0.70]); L = L / np.linalg.norm(L)
    diff = np.clip(-dx * L[0] * -1 * -1 + 0, 0, 0)  # placeholder (substituído abaixo)
    ndl = np.clip(dx * L[0] + dy * L[1] + z * L[2], 0, 1)
    base = np.array(col, np.float32)
    lum = (0.62 + 0.38 * ndl) if sum(col) > 600 else (0.30 + 0.70 * ndl)     # marfim: claro, sem virar cinza
    c = base * lum[..., None]
    # reflexo
    rx, ry = dx + 0.38, dy + 0.42
    spec = np.clip(1 - np.sqrt(rx * rx + ry * ry) / 0.28, 0, 1) ** 1.5
    c = c + (255 - c) * (spec[..., None] * 0.85)
    # borda escura
    edge = np.clip((d - 0.82) / 0.18, 0, 1)[..., None]
    c = c * (1 - 0.55 * edge)
    sub = sub * (1 - inside) + c * inside
    a[y0:y1, x0:x1] = np.clip(sub, 0, 255).astype(np.uint8)


def copy_patch(a, src_c, dst_c, r=14):
    """copia uma conta inteira (círculo) de um lugar para outro"""
    sx, sy = int(round(src_c[0])), int(round(src_c[1]))
    dx, dy = int(round(dst_c[0])), int(round(dst_c[1]))
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    m = (xx * xx + yy * yy) <= r * r
    patch = a[sy - r:sy + r + 1, sx - r:sx + r + 1].copy()
    tgt = a[dy - r:dy + r + 1, dx - r:dx + r + 1]
    tgt[m] = patch[m]


def diamond_mask(shape, c, hw, hh, grow=0):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    return (np.abs(xx - c[0]) / (hw + grow) + np.abs(yy - c[1]) / (hh + grow)) <= 1.0


def tile_mirror(patch, w, h, ox=0):
    """repete um retalho espelhado (sem emenda visível) até cobrir w x h"""
    ph, pw = patch.shape[:2]
    row = np.concatenate([patch, patch[:, ::-1]], axis=1)
    reps_x = int(np.ceil((w + ox) / row.shape[1])) + 1
    big = np.tile(row, (1, reps_x, 1))
    col = np.concatenate([big, big[::-1]], axis=0)
    reps_y = int(np.ceil(h / col.shape[0])) + 1
    big = np.tile(col, (reps_y, 1, 1))
    return big[:h, ox:ox + w]


def fill_table(a, hole):
    """Mesa sob as cartas da mão: veludo roxo (retalho da própria mesa, à esquerda), a borda dourada da mesa
    continuando o arco das laterais e o tapete verde atrás. Só aparece quando há menos de 4 cartas."""
    x0, x1, y0, y1 = 500, 1180, 740, a.shape[0]
    W, H = x1 - x0, y1 - y0
    velvet = tile_mirror(a[896:940, 504:538], W, H, 13)            # veludo liso (sem ornamento)
    reg = a[760:900, 360:520].reshape(-1, 3).astype(np.int32)
    green = np.median(reg[(reg[:, 1] > reg[:, 0] + 12) & (reg[:, 1] > reg[:, 2])], axis=0)
    rng = np.random.default_rng(57)
    carpet = np.clip(green[None, None, :] * (0.92 + 0.10 * rng.random((H, W, 1))), 0, 255)
    xs = np.arange(x0, x1)
    edge = 808 + 12 * ((xs - 835) / 290.0) ** 2           # arco da borda da mesa (y por coluna)
    yy = np.arange(y0, y1)[:, None]
    syn = np.where((yy >= edge[None, :])[..., None], velvet, carpet).astype(np.float32)
    # leve escurecimento do veludo junto da borda (sombra da moldura) e do tapete no alto
    dv = np.clip((yy - edge[None, :]) / 40.0, 0, 1)[..., None]
    syn = np.where((yy >= edge[None, :])[..., None], syn * (0.78 + 0.22 * dv), syn * 0.92)
    # moldura dourada: filete escuro + ouro + brilho, como a curva das laterais
    for off, col, wgt in ((-2.5, (40, 22, 6), 1.2), (0.0, (214, 160, 52), 1.3), (-1.0, (255, 226, 140), 0.6), (2.5, (40, 22, 6), 1.0)):
        dist = np.abs(yy - (edge[None, :] + off))
        al = np.clip(1.0 - dist / wgt, 0, 1)[..., None]
        syn = syn * (1 - al) + np.array(col, np.float32) * al
    out = a.copy().astype(np.float32)
    m = hole[y0:y1, x0:x1].astype(np.float32) / 255.0
    m = cv2.GaussianBlur(cv2.dilate(m, np.ones((5, 5), np.uint8)), (0, 0), 2.0)[..., None]
    out[y0:y1, x0:x1] = out[y0:y1, x0:x1] * (1 - m) + syn * m
    return np.clip(out, 0, 255).astype(np.uint8)


def fix_board(a):
    """Pátios e Portões nas cores certas de cada reino (com ou sem peões nos losangos)."""
    ox, oy = BOARD_CROP[0], BOARD_CROP[1]
    R = lambda p: (p[0] + ox, p[1] + oy)
    a = a.copy()
    # troca os losangos Marfim (creme) e Rubi (vermelho) de lugar: cada Pátio ao lado do próprio Portão
    cream_c, red_c = R((136.0, 173.5)), R((217.5, 517.0))
    def grab(c, hw, hh):
        x0, y0 = int(c[0] - hw - 6), int(c[1] - hh - 6)
        return a[y0:y0 + 2 * hh + 13, x0:x0 + 2 * hw + 13].copy()
    cr = grab(cream_c, 70, 63)
    rd = grab(red_c, 70, 63)
    for patch, c in ((cr, red_c), (rd, cream_c)):
        x0, y0 = int(c[0] - 70 - 6), int(c[1] - 63 - 6)
        ph, pw = patch.shape[:2]
        m = diamond_mask((ph, pw), (pw / 2.0, ph / 2.0), 70, 63, 5)
        tgt = a[y0:y0 + ph, x0:x0 + pw]
        tgt[m] = patch[m]
    # Portões nas cores certas de cada reino; o dourado do canto vira conta comum
    copy_patch(a, R((396.3, 604.4)), R((422.5, 606.0)))
    for seat in range(4):
        gx, gy = R(ARMS[seat][0])
        sphere(a, gx, gy, GATE_COLORS[seat])
    return a


def marcha_plate():
    a = load("marcha_partida.png")
    ox, oy = BOARD_CROP[0], BOARD_CROP[1]
    R = lambda p: (p[0] + ox, p[1] + oy)
    # 1) peões dos Pátios saem da arte (o jogo desenha os peões de verdade)
    diamonds = {"cream": ((136.0, 173.5), 69, 62), "black": ((525.0, 115.0), 66, 60), "red": ((217.5, 517.0), 68, 60), "green": ((597.5, 460.0), 66, 60)}
    for name, (c, hw, hh) in diamonds.items():
        cc = R(c)
        # o miolo inteiro do losango é refeito a partir da borda (os peões cobrem quase toda a placa)
        reg = diamond_mask(a.shape, cc, hw * 0.86, hh * 0.86)
        a = cv2.inpaint(a, reg.astype(np.uint8) * 255, 12, cv2.INPAINT_TELEA)
    a = fix_board(a)
    # 4) dados da partida saem da arte: subtítulo, nomes dos perfis, tempo da vez, cartas da mão
    m = np.zeros(a.shape[:2], np.uint8)
    m |= text_mask(a, (180, 50, 500, 78), "light")
    for box in [(782, 30, 1035, 82), (362, 405, 482, 450), (1312, 405, 1462, 450), (1432, 820, 1640, 872)]:
        m |= text_mask(a, box, "light")
    # tempo da vez (texto preto sobre o pergaminho): tudo que é escuro dentro da placa clara, menos a ampulheta
    x0, y0, x1, y1 = 140, 728, 322, 822
    sub = a[y0:y1, x0:x1].astype(np.int32)
    dark = (sub.max(axis=2) < 120).astype(np.uint8) * 255
    m[y0:y1, x0:x1] |= dark
    a = inpaint(a, m, grow=2, radius=4)
    # cartas: área grande — preenchimento por texturas vizinhas (FSR) para não ficar borrado
    cm = np.zeros(a.shape[:2], np.uint8)
    cards = [((616, 860), 152, 172, -4), ((763, 858), 140, 172, -1.5), ((910, 858), 140, 172, 1.5), ((1062, 862), 150, 172, 5)]
    for (cx, cy), w, h, ang in cards:
        box = cv2.boxPoints(((cx, cy), (w + 12, h + 12), ang)).astype(np.int32)
        cv2.fillConvexPoly(cm, box, 255)
    a = fill_table(a, cm)
    save(a, "marcha/art/r57/mesa.png")
    # botão JOGAR CARTA sem o texto (para "DESCARTAR CARTA")
    b = load("marcha_partida.png")
    bx0, by0, bx1, by1 = 62, 840, 335, 902
    bm = np.zeros(b.shape[:2], np.uint8)
    bm |= text_mask(b, (110, 850, 300, 892), "light")
    bb = inpaint(b, bm, 2, 4)
    save(bb[by0:by1, bx0:bx1], "marcha/art/r57/botao_jogar_vazio.png")


# ------------------------------------------------------------------ MARCHA REAL · antes da partida (referência 4)
def marcha_lobby():
    a = load("marcha_lobby.png")
    # o tabuleiro do painel da direita é o MESMO tabuleiro aprovado da partida (referência 3, cores certas),
    # com os peões nos Pátios — encaixado na moldura do painel
    b = fix_board(load("marcha_partida.png"))
    x0, y0, x1, y1 = BOARD_CROP
    board = b[y0:y1, x0:x1]
    ix0, iy0, ix1, iy1 = 880, 170, 1295, 555
    w = ix1 - ix0
    h = int(round(board.shape[0] * w / board.shape[1]))
    small = cv2.resize(board, (w, h), interpolation=cv2.INTER_AREA)
    a[iy0:iy1, ix0:ix1] = np.array([16, 11, 18], np.uint8)
    ty = iy0 + (iy1 - iy0 - h) // 2
    a[ty:ty + h, ix0:ix1] = small
    save(a, "marcha/art/r57/salao.png")
    # face do JOGAR AGORA sem texto (para "CONHECER CLUB FRAIHA" quando não há acesso)
    m = text_mask(a, (520, 592, 975, 650), "light")
    b = inpaint(a, m, 2, 4)
    save(b[580:661, 485:1011], "marcha/art/r57/botao_jogar_agora_vazio.png")


def main():
    xeque_plate("xeque_derrota.png", "xeque/art/telas/r57_derrota.png", "xeque/art/telas/r57_joias_derrota.png")
    xeque_plate("xeque_vitoria.png", "xeque/art/telas/r57_vitoria.png", "xeque/art/telas/r57_joias_vitoria.png")
    write_layout()
    marcha_plate()
    marcha_lobby()
    print("ok")


if __name__ == "__main__":
    main()
