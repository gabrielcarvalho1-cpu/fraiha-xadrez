"""R37 · MARCHA REAL: peão que entra no Salão do Trono vira DAMA.

Gera marcha/art/pawns/peao_<reino>_dama.png a partir da própria arte do peão de cada reino, para a dama
ter exatamente o mesmo material (marfim, rubi, ônix, esmeralda), o mesmo ouro e o mesmo contorno:
  • base e saia: as fileiras do peão da gola para baixo (o corpo fica 45% mais alto — a dama é alta);
  • gola dourada: a do peão;
  • taça que se abre para cima, anel dourado, 5 pontas de coroa com pérolas e a pérola do topo:
    desenhadas aqui, sombreadas com o perfil de luz tirado do próprio peão (corpo e anel dourado).
Saída com 1 px de contorno escuro, como a arte original."""
import os
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
P = os.path.join(ROOT, "marcha/art/pawns")
KINGDOMS = ["marfim", "rubi", "onix", "esmeralda"]


def profile(row_rgba):
    """Perfil horizontal de cor (luz de cilindro) de uma fileira: devolve f(u) com u em 0..1."""
    xs = np.where(row_rgba[:, 3] > 128)[0]
    seg = row_rgba[xs[0] + 2:xs[-1] - 1, :3].astype(np.float64)
    n = len(seg)
    def f(u):
        u = np.clip(u, 0, 1) * (n - 1)
        i = np.floor(u).astype(int)
        j = np.minimum(i + 1, n - 1)
        t = (u - i)[..., None]
        return seg[i] * (1 - t) + seg[j] * t
    return f


def solid(canvas, mask, prof, cx, half_w_of_y, shade_y=None):
    """Pinta os pixels de mask com o perfil (u = posição horizontal dentro da largura daquela fileira)."""
    ys, xs = np.where(mask)
    hw = np.maximum(1.0, half_w_of_y(ys))
    u = (xs - (cx - hw)) / (2 * hw)
    col = prof(u)
    if shade_y is not None: col = col * shade_y(ys)[:, None]
    canvas[ys, xs, :3] = np.clip(col, 0, 255)
    canvas[ys, xs, 3] = 255


def build(name):
    src = np.array(Image.open(os.path.join(P, f"peao_{name}.png")).convert("RGBA"))
    H0, W = src.shape[:2]
    cx = W / 2.0 - 0.5
    body_prof = profile(src[180])
    gold_prof = profile(src[124])
    head_prof = profile(src[60])
    # --- parte de baixo: gola (108) até o fim; o corpo (140–192) fica 45% mais alto
    collar = src[106:138]
    body = src[138:194]
    body = cv2.resize(body, (W, int(body.shape[0] * 1.45)), interpolation=cv2.INTER_NEAREST)
    base = src[194:H0]
    lower = np.concatenate([collar, body, base], axis=0)
    OFF = 24                                    # folga em cima para a pérola do topo
    TOP = 150 + OFF                             # altura da parte de cima (taça + coroa)
    H = TOP + lower.shape[0]
    out = np.zeros((H, W, 4), np.float64)
    out[TOP:] = lower
    yy, xx = np.mgrid[0:H, 0:W]
    # --- taça: de 30 px de meia-largura (em cima da gola) até 56 px, curva suave
    c_bot, c_top = TOP + 4, 62 + OFF
    def cup_hw(y):
        t = np.clip((c_bot - y) / float(c_bot - c_top), 0, 1)
        return 26 + 32 * t ** 1.6
    cup = (yy >= c_top) & (yy <= c_bot) & (np.abs(xx - cx) <= cup_hw(yy))
    solid(out, cup, body_prof, cx, cup_hw, lambda y: 0.82 + 0.18 * np.clip((c_bot - y) / 80.0, 0, 1))
    # --- anel dourado no alto da taça
    r_top, r_bot = 50 + OFF, 66 + OFF
    ring_hw = lambda y: np.full_like(y, 64, dtype=np.float64)
    ring = (yy >= r_top) & (yy <= r_bot) & (np.abs(xx - cx) <= 64)
    solid(out, ring, gold_prof, cx, ring_hw, lambda y: 1.05 - 0.35 * np.abs((y - (r_top + r_bot) / 2) / 8.0))
    # --- 5 pontas da coroa (triângulos dourados) com pérolas
    pearls = []
    for k, (dx, h, lean) in enumerate([(-48, 30, -10), (-24, 38, -4), (0, 42, 0), (24, 38, 4), (48, 30, 10)]):
        tipx, tipy = cx + dx + lean, r_top - h
        pts = np.array([[cx + dx - 11, r_top + 1], [cx + dx + 11, r_top + 1], [tipx, tipy]], np.int32)
        m = np.zeros((H, W), np.uint8)
        cv2.fillPoly(m, [pts], 1)
        solid(out, m.astype(bool), gold_prof, cx + dx, lambda y: np.full_like(y, 12, dtype=np.float64),
              lambda y: 0.85 + 0.25 * np.clip((r_top - y) / float(h), 0, 1))
        pearls.append((tipx, tipy - 4, 9 if k != 2 else 0))
    # pérolas nas pontas + pérola grande no topo (material do peão, como a cabeça dele)
    pearls.append((cx, r_top - 42 - 14, 15))
    for px, py, r in pearls:
        if r == 0: continue
        d = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
        m = d <= r
        u = np.clip((xx - (px - r)) / (2.0 * r), 0, 1)
        v = np.clip((yy - (py - r)) / (2.0 * r), 0, 1)
        col = head_prof(u[m]) * (1.08 - 0.45 * v[m])[:, None]
        out[m, :3] = np.clip(col, 0, 255)
        out[m, 3] = 255
    # --- contorno escuro de 2 px (como a arte do peão) e corte das sobras
    alpha = (out[..., 3] > 128).astype(np.uint8)
    ring2 = cv2.dilate(alpha, np.ones((5, 5), np.uint8)) - alpha
    edge = src[108, int(cx), :3] if src[108, int(cx), 3] > 128 else np.array([14, 8, 0])
    out[ring2 > 0, :3] = np.array([24, 16, 6])
    out[ring2 > 0, 3] = 255
    ys = np.where(out[..., 3] > 0)[0]
    out = out[max(0, ys.min() - 1):]
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    dst = os.path.join(P, f"peao_{name}_dama.png")
    img.save(dst, optimize=True)
    print(dst, img.size)


for k in KINGDOMS: build(k)
