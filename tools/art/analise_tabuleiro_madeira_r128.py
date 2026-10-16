#!/usr/bin/env python3
"""R128 · ANÁLISE: tabuleiro igual ao da partida Madeira (mesma arte do tabuleiro do PC: moldura de tronco com
cipós e casas de grama/areia). Recorta o tabuleiro de ranked/art/board_pc.png com a moldura em volta.
Saída analysis/art/tabuleiro_madeira.png + a fração da moldura (MARGEM / lado da grade) usada no review_board.gd.
Uso: python3 tools/art/analise_tabuleiro_madeira_r128.py"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
BOARD = (382, 145, 694)   # x, y, lado da grade de 8x8 na arte (ranked/board_skin.gd: Rect2(382, 145.5, 693.5, 694))
M = 48                    # moldura de tronco em volta da grade
im = Image.open(os.path.join(ROOT, "ranked/art/board_pc.png")).convert("RGB")
x, y, s = BOARD
out = im.crop((x - M, y - M, x + s + M, y + s + M))
out.save(os.path.join(ROOT, "analysis/art/tabuleiro_madeira.png"), optimize=True)
print(out.size, "moldura/lado = %.5f" % (M / s))
