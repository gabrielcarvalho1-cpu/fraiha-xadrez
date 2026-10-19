#!/usr/bin/env python3
"""R153 · HOME DEITADA (celular deitado, tela larga): recortes da arte da Home (home_forest_v9.png) com borda
suave (alfa) para o jogo reposicionar nas laterais: placa SEJA MEMBRO, 2 quadros de ícones, logo, cartão de
perfil e placa da conta. O menu do meio fica na arte, ampliado para ocupar a altura da tela.
Saída: ui_v022/assets/home_wide_<nome>.png. Os retângulos são os mesmos de main_hub.gd (WIDE_PATCHES)."""
import numpy as np
from PIL import Image
SRC = 'ui_v022/assets/home_forest_v9.png'
PATCHES = {   # nome: (x, y, w, h, borda suave)
    'club': (10, 4, 354, 84, 6),
    'icons': (356, 6, 146, 82, 6),
    'logo': (470, 0, 732, 312, 28),
    'profile': (1210, 18, 446, 232, 8),
    'account': (20, 832, 354, 100, 7),
}
art = np.asarray(Image.open(SRC).convert('RGBA')).astype(float)
for name, (x, y, w, h, f) in PATCHES.items():
    p = art[y:y + h, x:x + w].copy()
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum.reduce([xx, w - 1 - xx, yy, h - 1 - yy]).astype(float)
    a = np.clip(d / f, 0, 1) ** 1.5
    p[..., 3] *= a
    if name == 'profile':
        # a frase da arte sai do recorte: o jogo escreve a frase/status por cima (senão ficavam duas, desencontradas)
        import cv2
        rgb = np.ascontiguousarray(p[..., :3].clip(0, 255).astype(np.uint8))
        lum = rgb.mean(axis=2)
        mask = np.zeros(lum.shape, np.uint8)
        x0, y0, x1, y1 = 92, 146, 384, 194
        mask[y0:y1, x0:x1] = (lum[y0:y1, x0:x1] > 70).astype(np.uint8) * 255
        mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
        p[..., :3] = cv2.inpaint(rgb, mask, 4, cv2.INPAINT_TELEA)
    Image.fromarray(p.clip(0, 255).astype(np.uint8)).save(f'ui_v022/assets/home_wide_{name}.png')
    print(name, w, h)
