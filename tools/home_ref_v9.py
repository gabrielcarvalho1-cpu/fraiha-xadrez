"""R64 · Home v9 (PC) = arte v8 + BOTÕES DO MENU da nova referência do dono (tools/home_ref/home_referencia_r64_pc.png).

Só o miolo do menu entre os pilares (botões com ícones, textos, setas e selos NOVO) vem da referência;
o resto da arte (cenário, logo, placas vivas) continua o da v8. A borda do recorte é misturada em degradê
para não deixar emenda. Os textos dos botões passam a ficar NA ARTE (iguais à referência) e a Home desenha
a arte com filtro linear + mipmaps (sem serrilhado ao ampliar/reduzir na Web).
Saídas: ui_v022/assets/home_forest_v9.png e home_forest_v9_wide.png (largura +84 px de cada lado, R43).
Uso: python3 tools/home_ref_v9.py [raiz_do_repo]"""
import sys
import numpy as np
from PIL import Image, ImageFilter

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
A = ROOT + '/ui_v022/assets/'
REF = ROOT + '/tools/home_ref/home_referencia_r64_pc.png'
BOX = (588, 318, 1062, 884)      # miolo do menu (pilares e tochas inclusos)
FEATHER = 8
WIDE_PAD = 84

ref = np.asarray(Image.open(REF).convert('RGB')).astype(np.float64)
mask = Image.new('L', (1672, 941), 0)
inner = Image.new('L', (BOX[2] - BOX[0] - 2 * FEATHER, BOX[3] - BOX[1] - 2 * FEATHER), 255)
mask.paste(inner, (BOX[0] + FEATHER, BOX[1] + FEATHER))
m = np.asarray(mask.filter(ImageFilter.GaussianBlur(FEATHER / 2))).astype(np.float64)[..., None] / 255.0


def mix(base_path, out_path, dx):
    base = np.asarray(Image.open(base_path).convert('RGB')).astype(np.float64)
    h, w = 941, 1672
    sub = base[:, dx:dx + w]
    base[:, dx:dx + w] = sub * (1 - m) + ref * m
    Image.fromarray(np.clip(base + 0.5, 0, 255).astype(np.uint8)).save(out_path, optimize=True)


mix(A + 'home_forest_v8.png', A + 'home_forest_v9.png', 0)
mix(A + 'home_forest_v8_wide.png', A + 'home_forest_v9_wide.png', WIDE_PAD)
print('OK v9')
