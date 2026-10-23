#!/usr/bin/env python3
"""R178 · barra de baixo da Home do celular com 5 abas: INÍCIO · AMIGOS · PASSE · MINHA CONTA · MAIS.

Parte da própria arte (ui_v022/assets/home_mobile_v8.png, faixa y 1655→1842): o miolo do painel é refeito com a
cor de cada linha (sem ícones nem divisórias), as divisórias da arte são copiadas para as 4 novas posições, os
ícones da arte voltam centralizados nas novas casas e entra um ícone novo de COROA (PASSE) no mesmo estilo
(silhueta dourada chapada, como os outros). O losango azul do topo fica em cima da aba do meio (PASSE).
Saída: ui_v022/assets/home_nav5.png (854 x 187).
"""
import os
import numpy as np
import cv2
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = 1655
IN_Y = (45, 153)      # miolo do painel (y na faixa)
IN_X = (31, 823)
CELL_L, CELL_R = 30.0, 826.0
N = 5
OLD_SEPS = [214, 638]          # divisórias simples da arte (a do meio tem o losango)
OLD_ICONS = [(22, 214), (214, 425), (425, 638), (638, 835)]   # casas antigas (x)


def cells():
    w = (CELL_R - CELL_L) / N
    return [(CELL_L + i * w, CELL_L + (i + 1) * w) for i in range(N)]


def main():
    art = cv2.cvtColor(cv2.imread(os.path.join(ROOT, "ui_v022/assets/home_mobile_v8.png")), cv2.COLOR_BGR2RGB)
    R = art[TOP:].astype(np.float32).copy()
    H, W, _ = R.shape
    L = R @ np.array([0.299, 0.587, 0.114], np.float32)
    gold = (R[..., 0] > 150) & (R[..., 1] > 80) & (R[..., 0] - R[..., 2] > 60)
    # --- ícones antigos (máscara dourada + contorno), antes de apagar
    icons = []
    for (a, b) in OLD_ICONS:
        cx = (a + b) / 2.0
        x0, x1 = int(cx - 70), int(cx + 70)
        m = np.zeros((H, W), bool)
        m[52:132, x0:x1] = gold[52:132, x0:x1]
        lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=2))
        keep = np.zeros_like(m)
        for i in range(1, n + 1):
            comp = lab == i
            if comp.sum() > 40: keep |= comp
        ys, xs = np.nonzero(keep)
        bb = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
        alpha = ndimage.binary_fill_holes(ndimage.binary_dilation(keep, iterations=2)).astype(np.float32)
        alpha = cv2.GaussianBlur(alpha, (0, 0), 1.0)
        icons.append((R[bb[1]:bb[3], bb[0]:bb[2]].copy(), alpha[bb[1]:bb[3], bb[0]:bb[2]].copy(), bb))
    # --- divisória (com os enfeites de cima e de baixo)
    sx = OLD_SEPS[0]
    sep = R[36:162, sx - 18:sx + 19].copy()
    sep_a = np.clip((L[36:162, sx - 18:sx + 19] - 55) / 60.0, 0, 1)
    # --- losango do topo (aba do meio)
    dia = R[0:62, 392:462].copy()
    dia_L = L[0:62, 392:462]
    dm = ndimage.binary_fill_holes(ndimage.binary_closing(dia_L > 60, iterations=2))
    dm[44:, :28] = False
    dm[44:, 42:] = False                                                # embaixo da borda: só a ponta do losango
    dia_a = cv2.GaussianBlur(dm.astype(np.float32), (0, 0), 0.7)
    # --- apaga os enfeites das divisórias antigas que passam da borda (em cima e embaixo): coluna limpa da borda
    clean_x = 300
    for ox in (214, 425, 638):
        for (ya, yb) in ((30, 46), (150, 166)):
            col = R[ya:yb, clean_x:clean_x + 1].copy()
            R[ya:yb, ox - 22:ox + 23] = np.repeat(col, 45, axis=1)
    # --- miolo liso: cor mediana de cada linha nas partes sem nada
    plain_cols = list(range(250, 290)) + list(range(470, 500)) + list(range(560, 600)) + list(range(775, 815))
    y0, y1 = IN_Y
    x0, x1 = IN_X
    for y in range(y0, y1):
        row = np.median(R[y, plain_cols], axis=0)
        R[y, x0:x1] = row
    rng = np.random.default_rng(3)
    R[y0:y1, x0:x1] += rng.normal(0, 1.6, (y1 - y0, x1 - x0, 1)).astype(np.float32)
    R[y0:y1, x0:x1] = cv2.GaussianBlur(R[y0:y1, x0:x1], (3, 1), 0)
    cs = cells()
    # brilho quente da aba ativa (INÍCIO), como na arte
    gy, gx = np.mgrid[0:H, 0:W]
    c0 = ((cs[0][0] + cs[0][1]) / 2.0, 100.0)
    glow = np.exp(-(((gx - c0[0]) / 70.0) ** 2 + ((gy - c0[1]) / 60.0) ** 2))
    inside = np.zeros((H, W), np.float32)
    inside[y0:y1, int(cs[0][0]) + 2:int(cs[0][1]) - 2] = 1
    inside = cv2.GaussianBlur(inside, (0, 0), 3)
    gcol = np.array([150, 95, 20], np.float32)
    R += (glow * inside * 0.55)[..., None] * (gcol - R) * 0.6
    # brilho azul suave na aba do PASSE (destaque)
    c2 = ((cs[2][0] + cs[2][1]) / 2.0, 92.0)
    glow2 = np.exp(-(((gx - c2[0]) / 62.0) ** 2 + ((gy - c2[1]) / 52.0) ** 2))
    inside2 = np.zeros((H, W), np.float32)
    inside2[y0:y1, int(cs[2][0]) + 2:int(cs[2][1]) - 2] = 1
    inside2 = cv2.GaussianBlur(inside2, (0, 0), 3)
    R += (glow2 * inside2 * 0.35)[..., None] * (np.array([70, 110, 200], np.float32) - R) * 0.6
    # divisórias novas
    for i in range(1, N):
        x = int(round(cs[i][0]))
        a0 = x - 18
        sub = R[36:162, a0:a0 + 37]
        sub[:] = sub * (1 - sep_a[..., None]) + sep * sep_a[..., None]
    # losango em cima da aba do meio
    mx = int(round((cs[2][0] + cs[2][1]) / 2.0)) - 35
    sub = R[0:62, mx:mx + 70]
    sub[:] = sub * (1 - dia_a[..., None]) + dia * dia_a[..., None]
    # ícones nas casas novas (INÍCIO, AMIGOS, [PASSE], CONTA, MAIS)
    slots = [0, 1, 3, 4]
    for (img, al, bb), slot in zip(icons, slots):
        cx = (cs[slot][0] + cs[slot][1]) / 2.0
        h, w = al.shape
        px = int(round(cx - w / 2.0))
        py = bb[1]
        sub = R[py:py + h, px:px + w]
        sub[:] = sub * (1 - al[..., None]) + img * al[..., None]
    # ícone novo: coroa chapada dourada (mesmo degradê dos outros ícones)
    crown = cv2.imread(os.path.join(ROOT, "marcha/art/coroa_coroacao.png"), cv2.IMREAD_UNCHANGED)
    ca = crown[..., 3].astype(np.float32) / 255.0
    ys, xs = np.nonzero(ca > 0.5)
    ca = ca[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    th = 60
    tw = int(round(ca.shape[1] * th / ca.shape[0]))
    ca = cv2.resize(ca, (tw, th), interpolation=cv2.INTER_AREA)
    ca = np.clip((ca - 0.15) / 0.7, 0, 1)
    # degradê do ícone dos AMIGOS (claro em cima → laranja embaixo)
    top_c = np.array([255, 205, 70], np.float32)
    bot_c = np.array([236, 140, 18], np.float32)
    grad = np.linspace(0, 1, th)[:, None, None]
    fill = top_c * (1 - grad) + bot_c * grad
    fill = np.repeat(fill, tw, axis=1)
    # relevo: a luz da própria coroa (claro/escuro) marca arcos, cruz e aro, como os ícones da arte
    lum = cv2.cvtColor(crown[..., :3], cv2.COLOR_BGR2GRAY).astype(np.float32)[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    lum = cv2.resize(lum, (tw, th), interpolation=cv2.INTER_AREA) / 255.0
    lum = (lum - lum[ca > 0.5].min()) / max(1e-3, np.ptp(lum[ca > 0.5]))
    fill = fill * (0.62 + 0.5 * lum[..., None])
    # filete claro e sombra embaixo, como os outros
    shadow = cv2.GaussianBlur(ca, (0, 0), 2.0)
    cx = (cs[2][0] + cs[2][1]) / 2.0
    px = int(round(cx - tw / 2.0))
    py = 56
    sub = R[py + 3:py + 3 + th, px:px + tw]
    sub[:] = sub * (1 - 0.55 * shadow[..., None])
    sub = R[py:py + th, px:px + tw]
    sub[:] = sub * (1 - ca[..., None]) + fill * ca[..., None]
    out = np.clip(R, 0, 255).astype(np.uint8)
    cv2.imwrite(os.path.join(ROOT, "ui_v022/assets/home_nav5.png"), cv2.cvtColor(out, cv2.COLOR_RGB2BGR))
    print("ok", out.shape, [round(a, 1) for a, _ in cs])


if __name__ == "__main__":
    main()
