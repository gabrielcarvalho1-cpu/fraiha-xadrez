"""R35.1 · XEQUE: versões da cena da mesa para a tela sem "caixa preta".
 - mesa_cena_soft.png: a cena aprovada com as bordas laterais (70 px) e de baixo (90 px) esfumadas (alfa).
 - mesa_cena_blur.png: a mesma cena desfocada (fundo que cobre a janela inteira, atrás da cena nítida).
Os pixels de dentro da cena não mudam."""
import os
import numpy as np
from PIL import Image, ImageFilter
ROOT = os.path.join(os.path.dirname(__file__), "..")
D = os.path.join(ROOT, "xeque/art/mesa")
src = Image.open(os.path.join(D, "mesa_cena_com_tapete.png")).convert("RGBA")
w, h = src.size
x = np.arange(w)[None, :].astype(float)
y = np.arange(h)[:, None].astype(float)
a = np.minimum(np.minimum(np.clip(x / 70.0, 0, 1), np.clip((w - 1 - x) / 70.0, 0, 1)), np.clip((h - 1 - y) / 90.0, 0, 1))
a = a * a * (3 - 2 * a)
arr = np.array(src).astype(float)
arr[..., 3] = arr[..., 3] * a
Image.fromarray(arr.astype(np.uint8)).save(os.path.join(D, "mesa_cena_soft.png"))
blur = src.convert("RGB").resize((w // 4, h // 4), Image.LANCZOS).filter(ImageFilter.GaussianBlur(10))
blur.save(os.path.join(D, "mesa_cena_blur.png"))
print("ok", w, h)
