#!/usr/bin/env python3
"""R126 · XEQUE: arte do anúncio "XEQUE!" (aparece quando alguém pede xeque), arte do dono.
Corta a borda transparente e reduz para 1600 px de largura. Saída xeque/art/interface/xeque_anuncio_r126.png.
Uso: python3 tools/art/xeque_anuncio_r126.py <arte.png>"""
import sys, os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
src = Image.open(sys.argv[1]).convert("RGBA")
src = src.crop(src.getchannel("A").getbbox())
w = 1600
out = src.resize((w, round(src.height * w / src.width)), Image.LANCZOS)
out.save(os.path.join(ROOT, "xeque/art/interface/xeque_anuncio_r126.png"), optimize=True)
print(out.size)
