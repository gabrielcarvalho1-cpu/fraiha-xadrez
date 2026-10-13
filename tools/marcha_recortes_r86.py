"""R86 · Marcha em pé: recorta da arte da mesa (marcha/art/r57/mesa.png) o painel SUA VEZ + JOGAR CARTA e o
título MARCHA REAL com fundo transparente (sem o pedaço de parede/feltro em volta), para assentar no cenário."""
import sys, os
import numpy as np
from PIL import Image, ImageFilter
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = np.asarray(Image.open(os.path.join(ROOT, "marcha/art/r57/mesa.png")).convert("RGB")).astype(np.int16)

def gold(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (r > 120) & (g > 80) & (r - b > 55) & (r >= g)

def cut(box, inner, band_gold=True, name="x"):
    x0, y0, x1, y1 = box
    a = src[y0:y1, x0:x1]
    h, w = a.shape[:2]
    m = np.zeros((h, w), np.uint8)
    ix0, iy0, ix1, iy1 = [v - o for v, o in zip(inner, (x0, y0, x0, y0))]
    m[iy0:iy1, ix0:ix1] = 255
    if band_gold:
        # ornamentos dourados da moldura: só na faixa colada no miolo (sem pedaços soltos da arte vizinha)
        yy, xx = np.mgrid[0:h, 0:w]
        dx = np.maximum(np.maximum(ix0 - xx, xx - (ix1 - 1)), 0)
        dy = np.maximum(np.maximum(iy0 - yy, yy - (iy1 - 1)), 0)
        near = np.maximum(dx, dy) <= 9
        g = gold(a) & near
        m[g] = 255
    im = Image.fromarray(m).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = Image.fromarray(a.astype(np.uint8)).convert("RGBA")
    out.putalpha(im)
    out.save(os.path.join(ROOT, "marcha/art/r86", name))
    print(name, out.size)

# painel: retângulo da arte usado no celular = (30, 640, 330x280); o miolo vai até a linha dourada
cut((30, 640, 360, 920), (39, 646, 352, 917), True, "painel_vez.png")
