#!/usr/bin/env python3
"""R114 · lobby (Home) em azul: só as áreas dos botões/cartões da arte da Home (a floresta fica verde).
Usa a mesma regra de tools/art/verde_para_azul.py. Rodar uma vez (grava por cima; o original fica no git)."""
import importlib.util, os, numpy as np
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('v', os.path.join(here, 'verde_para_azul.py')); v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)

def rec(a):
    rgb = a[..., :3]; h, s, val = v.rgb_to_hsv(rgb)
    w = np.clip((h - v.LO0) / (v.LO1 - v.LO0), 0, 1) * np.clip((v.HI0 - h) / (v.HI0 - v.HI1), 0, 1) * np.clip((s - v.S_MIN) / 0.08, 0, 1)
    v2 = np.clip(val * (1 + v.V_LIFT * (1 - val)), 0, 1)
    new = v.hsv_to_rgb(np.full_like(h, v.H_TARGET), s, v2)
    a[..., :3] = rgb * (1 - w[..., None]) + new * w[..., None]

def regions(path, boxes, scale=1.0, dx=0):
    im = Image.open(path); mode = im.mode
    a = np.asarray(im.convert('RGBA')).astype(float) / 255
    for x0, y0, x1, y1 in boxes:
        X0, Y0, X1, Y1 = [int(round(c * scale)) for c in (x0, y0, x1, y1)]
        sub = a[Y0:Y1, X0 + dx:X1 + dx].copy(); rec(sub); a[Y0:Y1, X0 + dx:X1 + dx] = sub
    out = Image.fromarray((a * 255 + .5).clip(0, 255).astype(np.uint8), 'RGBA')
    (out if mode == 'RGBA' else out.convert('RGB')).save(path, optimize=True)
    print('ok', path)

PC = [(15, 10, 770, 82), (595, 255, 1058, 880), (1205, 35, 1662, 242), (25, 840, 368, 928)]
CEL = [(5, 18, 428, 70), (48, 243, 382, 350), (52, 355, 380, 690), (3, 845, 428, 928)]
A = 'ui_v022/assets/'
regions(A + 'home_forest_v9.png', PC)
regions(A + 'home_forest_v9_wide.png', PC, dx=84)
regions(A + 'home_mobile_v8.png', CEL, scale=854 / 430)
for f in [A + 'menu_atlas.png', 'ui_v022/art/home_profile_frame.png', 'ui_v022/art/home_profile_under.png', A + 'home_account_plaque.png',
          A + 'home_profile_card.png', A + 'home_ranked_row.png', A + 'home_row_blank.png', A + 'home_row_marcha.png', A + 'home_row_xeque.png', A + 'r86/escudo_vazio.png']:
    print('%5.1f%%  %s' % (100 * v.convert(f), f))
