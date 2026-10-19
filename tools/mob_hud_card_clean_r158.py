#!/usr/bin/env python3
"""R158 · cartão do jogador da partida (celular deitado) LIMPO: a arte antiga era um recorte de print, com folhas,
pedaço de poste e grama nas bordas. Este é montado com as mesmas cores da arte (trilho dourado de cima/baixo e miolo
azul), com a borda dourada contínua nos 4 lados e cantos de quina."""
import numpy as np
from PIL import Image
a = np.asarray(Image.open('ranked/art/mob_hud_card.png').convert('RGBA')).astype(float)
W, H, B = 714, 114, 16                   # largura, altura, espessura da borda
col = a[:, 360]                          # perfil vertical no meio (sem as sobras das pontas)
top = col[0:B]                           # trilho de cima (madeira + filete dourado)
mid = col[B:100]                         # miolo azul
bot = col[100:100 + B]                   # trilho de baixo
# miolo: o perfil vertical esticado na altura certa
mh = H - 2 * B
idx = np.linspace(0, len(mid) - 1, mh).round().astype(int)
prof = np.concatenate([top, mid[idx], bot], axis=0)          # (H, 4)
out = np.repeat(prof[:, None, :], W, axis=1)
# laterais: o mesmo trilho de cima, girado (o lado de fora é a madeira, o de dentro o filete dourado)
side = top                                                    # (B, 4)
for x in range(B):
    out[B - 1 - 0:H - B + 1, x] = side[x]
    out[B - 1 - 0:H - B + 1, W - 1 - x] = side[x]
# quinas em 45°: cada canto pega o trilho mais perto
for y in range(B):
    for x in range(B):
        if x < y:   # metade de baixo do canto → lateral
            out[y, x] = side[x]; out[y, W - 1 - x] = side[x]
            out[H - 1 - y, x] = side[x]; out[H - 1 - y, W - 1 - x] = side[x]
out[..., 3] = 255
Image.fromarray(out.clip(0, 255).astype(np.uint8)).save('ranked/art/mob_hud_card_clean.png')
print(out.shape)
