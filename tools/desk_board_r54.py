#!/usr/bin/env python3
"""R54 · Tabuleiro do PC (Ranked Madeira e contra o computador): tira da barra de cima o botão
MARCAR PARA REVISAR (função removida da partida). A casa do botão vira barra lisa, copiada do trecho
vazio da própria barra (onde fica o texto de status da voz), e o status ganha esse espaço.
Idempotente: rodar de novo não muda nada. Uso: python3 tools/desk_board_r54.py"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLOT = (1411, 12, 1462, 76)       # botão MARCAR na arte 1672 x 941 (com a borda da placa)
SRC_X = 1352                      # mesmo trecho da barra, sem nada desenhado
for name in ['board_pc.png', 'board_pc_bot.png']:
    p = os.path.join(ROOT, 'ranked', 'art', name)
    a = np.array(Image.open(p).convert('RGB'))
    x0, y0, x1, y1 = SLOT
    a[y0:y1, x0:x1] = a[y0:y1, SRC_X:SRC_X + (x1 - x0)]
    Image.fromarray(a).save(p, optimize=True)
    print(name, 'ok')
