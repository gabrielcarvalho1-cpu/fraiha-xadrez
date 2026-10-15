#!/usr/bin/env python3
"""R122 · painel MAIS do celular com a 5ª linha COMUNIDADE (entre CONHEÇA O FRAIHA e SAIR).
Duplica a faixa da linha CONHEÇA (com o conector de baixo), apaga o texto copiando o miolo liso da linha
VOLTAR e escreve COMUNIDADE no mesmo estilo (creme com contorno escuro).
Uso: python3 tools/art/mais_comunidade_r122.py  →  ui_kit/mobile/mais_panel_r122.png"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
src = Image.open(ROOT / "ui_kit/mobile/mais_panel.png").convert("RGBA")
W, H = src.size
Y0, Y1 = 966, 1160          # faixa da linha CONHEÇA (topo da moldura até o topo da linha SAIR)
P = Y1 - Y0                 # 194 px: altura de uma linha
out = Image.new("RGBA", (W, H + P))
out.paste(src.crop((0, 0, W, Y1)), (0, 0))
out.paste(src.crop((0, Y0, W, Y1)), (0, Y1))
out.paste(src.crop((0, Y1, W, H)), (0, Y1 + P))

# colunas das laterais (pilares): em vez da cópia (que corta a joia do pilar), estica um trecho liso do pilar
SIDE_Y = 1110               # linha lisa do pilar (entre as joias)
for (xa, xb) in [(0, 94), (806, W)]:
    out.paste(src.crop((xa, 0, xb, SIDE_Y)), (xa, 0))
    row = src.crop((xa, SIDE_Y, xb, SIDE_Y + 1))
    for y in range(SIDE_Y, SIDE_Y + P): out.paste(row, (xa, y))
    out.paste(src.crop((xa, SIDE_Y, xb, H)), (xa, SIDE_Y + P))

# apaga "CONHEÇA O FRAIHA" da cópia: miolo liso da linha VOLTAR (mesma altura relativa)
DV = 969 - 582              # distância entre as linhas VOLTAR e CONHEÇA
ty0, ty1 = 1004, 1086       # faixa do texto na linha CONHEÇA
strip = src.crop((192, ty0 - DV, 322, ty1 - DV))
for x in range(186, 712, strip.width):
    w = min(strip.width, 712 - x)
    out.paste(strip.crop((0, 0, w, strip.height)), (x, ty0 - Y0 + Y1))

# texto COMUNIDADE
font = ImageFont.truetype(str(ROOT / "account/fonts/Cinzel-Bold.woff"), 62)
text = "COMUNIDADE"
cy = (1045 - Y0) + Y1
d = ImageDraw.Draw(out)
bb = d.textbbox((0, 0), text, font=font, anchor="ls")
tw = bb[2] - bb[0]
x = (W - tw) // 2
base = cy + 22
# sombra + contorno
shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
ImageDraw.Draw(shadow).text((x + 3, base + 4), text, font=font, anchor="ls", fill=(0, 0, 0, 200), stroke_width=6, stroke_fill=(0, 0, 0, 200))
out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(2)))
d = ImageDraw.Draw(out)
d.text((x, base), text, font=font, anchor="ls", fill=(0, 0, 0, 0), stroke_width=5, stroke_fill=(24, 12, 2, 255))
# preenchimento creme em degradê (claro em cima, dourado-claro embaixo)
mask = Image.new("L", out.size, 0)
ImageDraw.Draw(mask).text((x, base), text, font=font, anchor="ls", fill=255, stroke_width=1, stroke_fill=255)   # um pouco mais grosso, como a arte
top, bot = bb[1] + base, base
grad = Image.new("RGBA", out.size)
gd = ImageDraw.Draw(grad)
for y in range(top - 2, bot + 6):
    t = max(0.0, min(1.0, (y - top) / max(1, bot - top)))
    c = (int(252 - 18 * t), int(248 - 50 * t), int(236 - 100 * t), 255)
    gd.line([(0, y), (W, y)], fill=c)
out.paste(grad, (0, 0), mask)
dst = ROOT / "ui_kit/mobile/mais_panel_r122.png"
out.save(dst)
print(dst.relative_to(ROOT), out.size)
