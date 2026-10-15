#!/usr/bin/env python3
"""R123 · tira o verde de uma arte trocando a matiz verde (100°–190°) por outra (bordô 338 / azul 220),
mantendo brilho, sombras e o dourado. Uso: python3 tools/art/recolor_verde_r123.py <hue> <v_mult> arquivo.png ..."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
import verde_para_azul as V

def recolor(path, hue, vmul, out=None):
    im = Image.open(path)
    src = np.asarray(im.convert("RGBA")).astype(float) / 255
    rgb = src[..., :3]
    h, s, v = V.rgb_to_hsv(rgb)
    w = np.clip((h - 95) / 10, 0, 1) * np.clip((195 - h) / 10, 0, 1) * np.clip((s - 0.08) / 0.08, 0, 1)
    v2 = np.clip(v * vmul, 0, 1) if vmul <= 1 else np.clip(v * (1 + (vmul - 1) * (1 - v)), 0, 1)
    new = V.hsv_to_rgb(np.full_like(h, hue), np.clip(s * 1.05, 0, 1), v2)
    res = rgb * (1 - w[..., None]) + new * w[..., None]
    Image.fromarray((np.concatenate([res, src[..., 3:]], -1) * 255 + .5).astype(np.uint8), "RGBA").save(out or path, optimize=True)

if __name__ == "__main__":
    hue, vmul = float(sys.argv[1]), float(sys.argv[2])
    for f in sys.argv[3:]: recolor(f, hue, vmul)
