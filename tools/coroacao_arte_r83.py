"""R83 · Coroação da Marcha Real: recorta a ARTE DE REFERÊNCIA do dono (tools/ui_ref/r83/coroacao_ref.png, 1254x1254)
em duas peças com fundo transparente — o EMBLEMA (escudo + coroa + brilho roxo) e o LETREIRO "COROADO" com a faixa.
Fundo escuro → transparente: o que é sólido (moldura, coroa, letras e o miolo preto do escudo, que fica fechado pela
moldura) é opaco; o brilho roxo vira transparência proporcional ao brilho (cor desfeita do fundo).
Uso: python3 tools/coroacao_arte_r83.py"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REF = os.path.join(ROOT, "tools/ui_ref/r83/coroacao_ref.png")
BG = np.array([10, 6, 17], np.float32)


def cutout(a):
    f = a.astype(np.float32)
    d = np.clip(f - BG, 0, None)
    mx = d.max(2)
    sat = f.max(2) - f.min(2)
    solid = (mx > 70) & (sat > 60) | (mx > 200)
    solid = ndimage.binary_closing(solid, iterations=2)
    solid = ndimage.binary_fill_holes(solid)
    glow = np.clip(mx / 255.0 * 1.35, 0, 1)
    alpha = np.maximum(solid.astype(np.float32), glow)
    alpha = ndimage.gaussian_filter(alpha, 0.6) * 0.5 + alpha * 0.5
    col = BG + d / np.maximum(alpha, 1e-3)[..., None]
    col = np.where(solid[..., None], f, col)
    out = np.dstack([np.clip(col, 0, 255), alpha * 255]).astype(np.uint8)
    return out


def main():
    a = np.array(Image.open(REF).convert("RGB"))
    rgba = cutout(a)
    emb = rgba[20:858, 60:1194]          # escudo + brilho (acima da faixa)
    ban = rgba[840:1080, 60:1194]        # faixa COROADO
    Image.fromarray(emb, "RGBA").save(os.path.join(ROOT, "marcha/art/coroacao_emblema.png"), optimize=True)
    Image.fromarray(ban, "RGBA").save(os.path.join(ROOT, "marcha/art/coroado_pixel.png"), optimize=True)
    print("ok", emb.shape, ban.shape)


if __name__ == "__main__":
    main()
