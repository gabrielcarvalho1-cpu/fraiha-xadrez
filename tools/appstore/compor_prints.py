# R191 · monta os prints da App Store (1290×2796, iPhone 6,9"): legenda em cima + tela do jogo com moldura dourada
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
SRC, OUT = sys.argv[1], sys.argv[2]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BOLD = os.path.join(ROOT, "account/fonts/Cinzel-Bold.woff")
SEMI = os.path.join(ROOT, "account/fonts/Cinzel-SemiBold.woff")
W, H = 1290, 2796
ITEMS = [
    ("01_home.png", "XADREZ COM RANKING", "do Madeira ao Challenger"),
    ("02_ranked.png", "PARTIDAS RANQUEADAS", "de 3 a 20 minutos, valendo liga"),
    ("05_marcha.png", "MARCHA REAL", "cartas e corrida de peões"),
    ("06_xeque.png", "XEQUE", "o jogo do blefe com peças de xadrez"),
]
GOLD, CREAM = (244, 206, 127), (239, 227, 196)

def background():
    top, bot = (13, 20, 48), (52, 14, 30)
    g = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return g.resize((W, H))

def centered(d, y, text, font, fill):
    w = d.textlength(text, font=font)
    d.text(((W - w) / 2, y), text, font=font, fill=fill)

for i, (fn, title, sub) in enumerate(ITEMS, 1):
    img = background()
    d = ImageDraw.Draw(img)
    size = 104
    ft = ImageFont.truetype(BOLD, size)
    while d.textlength(title, font=ft) > W - 120:
        size -= 4; ft = ImageFont.truetype(BOLD, size)
    centered(d, 120, title, ft, GOLD)
    centered(d, 120 + size + 34, sub, ImageFont.truetype(SEMI, 58), CREAM)
    shot = Image.open(os.path.join(SRC, fn)).convert("RGB")
    sw = 1080
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, 400
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x - 10, y - 10, x + sw + 10, y + sh + 10), 70, fill=170)
    img.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(28)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((x - 9, y - 9, x + sw + 9, y + sh + 9), 66, fill=(201, 160, 72))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), 58, fill=255)
    img.paste(shot, (x, y), mask)
    img.save(os.path.join(OUT, "FRAIHA_loja_%d.png" % i))
    print("ok", i, img.size)
