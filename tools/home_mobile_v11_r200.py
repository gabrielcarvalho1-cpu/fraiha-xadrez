#!/usr/bin/env python3
"""R200 · Home do celular em pé: MARCHA REAL e XEQUE sobem para as placas grandes (no lugar de JOGAR ONLINE e
CONTRA O COMPUTADOR, que descem para as placas pequenas com a observação "xadrez"). Troca só os ÍCONES dourados
da arte (coroa/cartas ↔ globo/monitor) e leva o selo NOVO para as placas grandes. Ícones: máscara do dourado,
o lugar antigo é preenchido com o azul da própria placa (inpaint), o novo entra redimensionado com borda suave.
Saída: ui_v022/assets/home_mobile_v11.png
"""
import os, cv2, numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = np.asarray(Image.open(os.path.join(ROOT, "ui_v022/assets/home_mobile_v10.png")).convert("RGB")).copy()
def gold(a):
    a = a.astype(int)
    return ((a[..., 0] > 140) & (a[..., 1] > 90) & (a[..., 2] < 140) & (a[..., 0] - a[..., 2] > 60)).astype(np.uint8) * 255
def cut(box):
    x0, y0, x1, y1 = box
    a = src[y0:y1, x0:x1].copy()
    m = cv2.dilate(gold(a), np.ones((3, 3), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    # o miolo escuro dos ícones (vazados) entra junto: preenche buracos fechados
    ff = m.copy(); h, w = m.shape; mm = np.zeros((h + 2, w + 2), np.uint8)
    cv2.floodFill(ff, mm, (0, 0), 255)
    m = m | cv2.bitwise_not(ff)
    return a, m
def erase(out, box, m):
    x0, y0, x1, y1 = box
    full = np.zeros(out.shape[:2], np.uint8)
    full[y0:y1, x0:x1] = cv2.dilate(m, np.ones((5, 5), np.uint8))
    return cv2.cvtColor(cv2.inpaint(cv2.cvtColor(out, cv2.COLOR_RGB2BGR), full, 7, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)
def paste(out, icon, m, center, height):
    ys, xs = np.where(m > 0)
    icon = icon[ys.min():ys.max() + 1, xs.min():xs.max() + 1]; m = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    k = height / icon.shape[0]
    W, H = max(1, int(round(icon.shape[1] * k))), int(round(height))
    ic = cv2.resize(icon, (W, H), interpolation=cv2.INTER_AREA if k < 1 else cv2.INTER_CUBIC)
    al = cv2.GaussianBlur(cv2.resize(m, (W, H), interpolation=cv2.INTER_LINEAR), (3, 3), 0).astype(np.float32)[..., None] / 255.0
    x0, y0 = int(center[0] - W / 2), int(center[1] - H / 2)
    reg = out[y0:y0 + H, x0:x0 + W].astype(np.float32)
    out[y0:y0 + H, x0:x0 + W] = (reg * (1 - al) + ic * al).astype(np.uint8)
    return out
BOX = {"globe": (170, 885, 255, 975), "monitor": (170, 1004, 255, 1092), "crown": (147, 1268, 210, 1322),
       "cards": (456, 1262, 534, 1328), "novo1": (332, 1268, 416, 1316), "novo2": (628, 1268, 714, 1316)}
parts = {k: cut(v) for k, v in BOX.items()}
out = src.copy()
for k in BOX: out = erase(out, BOX[k], parts[k][1])
# selos NOVO: a peça inteira (placa dourada com texto), retangular
novo = src[1270:1314, 333:415].copy()
out = paste(out, *parts["crown"], (212, 930), 64)       # MARCHA REAL na placa grande de cima
out = paste(out, *parts["cards"], (212, 1054), 70)      # XEQUE na placa grande de baixo
out = paste(out, *parts["globe"], (178, 1293), 40)      # JOGAR ONLINE na placa pequena da esquerda
out = paste(out, *parts["monitor"], (473, 1293), 38)    # CONTRA O COMPUTADOR na placa pequena da direita
for y in (896, 1020):                                   # NOVO no canto de cima das placas grandes
    out[y:y + novo.shape[0], 568:568 + novo.shape[1]] = novo
Image.fromarray(out).save(os.path.join(ROOT, "ui_v022/assets/home_mobile_v11.png"), optimize=True)
print("ok")
