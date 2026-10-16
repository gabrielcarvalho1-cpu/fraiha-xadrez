#!/usr/bin/env python3
"""R130 · ANÁLISE: fundo do painel do duelo = arte de carregamento (rei e dama dourados), só a faixa do meio
(sem o logo de cima e sem a barra "PREPARANDO O TABULEIRO"). Saída analysis/art/duelo_fundo.png.
Uso: python3 tools/art/analise_duelo_fundo_r130.py"""
import os
from PIL import Image
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
im = Image.open(os.path.join(ROOT, "branding/fraiha_loading_splash_r63.png")).convert("RGB")
band = im.crop((0, 168, 1672, 700))          # 1672 x 532: estandartes, tochas, rei e dama, piso
band.save(os.path.join(ROOT, "analysis/art/duelo_fundo.png"), optimize=True)
print(band.size)
