#!/usr/bin/env python3
"""R123 · verso das cartas do XEQUE sem o verde: fundo e raios recoloridos (azul-marinho do jogo e/ou bordô),
o brilho da coroa que puxava para o verde-oliva vira dourado. Dourado da moldura e da coroa não mudam.
Uso: python3 tools/art/xeque_verso_r123.py <fundo_hue> <medalhao_hue> <saida.png>
     (azul = 220, bordô = 350; ex.: 220 350 = fundo azul com medalhão bordô)"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
import verde_para_azul as V

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "xeque/art/cartas/carta_verso.png"   # arte original (verde) — sempre lida do git: git show HEAD~:...

def make(src_png, hue_out, hue_in, out_png):
    src = np.asarray(Image.open(src_png).convert("RGBA")).astype(float) / 255
    rgb = src[..., :3]
    h, s, v = V.rgb_to_hsv(rgb)
    green = (h > 100) & (h < 190) & (s > 0.12)
    lime = (h >= 58) & (h <= 100) & (s > 0.10)
    H, W = h.shape
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.hypot(xx - W / 2, yy - H / 2)
    hh = np.where(green, hue_out, h)
    hh = np.where(green & (r < 112), hue_in, hh)
    hh = np.where(lime, 44.0, hh)
    lift = 0.45 if hue_out == 220 else 0.25
    v2 = np.where(green, np.clip(v * (1 + lift * (1 - v)), 0, 1), v)
    v2 = np.where(lime, np.clip(v * 1.18, 0, 1), v2)
    s2 = np.where(green, np.clip(s * 1.1, 0, 1), s)
    s2 = np.where(lime, np.maximum(s, 0.5), s2)
    out = V.hsv_to_rgb(hh, s2, v2)
    out = np.where((green | lime)[..., None], out, rgb)
    Image.fromarray((np.concatenate([out, src[..., 3:]], -1) * 255 + .5).astype(np.uint8), "RGBA").save(out_png, optimize=True)

if __name__ == "__main__":
    make(SRC if len(sys.argv) < 5 else sys.argv[4], float(sys.argv[1]), float(sys.argv[2]), sys.argv[3])
