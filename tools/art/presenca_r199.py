# R199 · ícones de presença ONLINE / OFFLINE no estilo da arte: losango (gema) com moldura dourada, em vez das
# bolinhas verde/cinza. ONLINE = esmeralda acesa com brilho; OFFLINE = gema de ferro apagada.
from PIL import Image, ImageDraw, ImageFilter
S = 96; X = 4
def gem(top, mid, bot, glow, name):
    W = S * X
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    c = W / 2
    def dia(r): return [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]
    if glow:
        g = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        ImageDraw.Draw(g).polygon(dia(W * 0.46), fill=glow)
        im = Image.alpha_composite(im, g.filter(ImageFilter.GaussianBlur(W * 0.05)))
    d = ImageDraw.Draw(im)
    d.polygon(dia(W * 0.40), fill=(58, 34, 6, 255))               # contorno escuro
    d.polygon(dia(W * 0.37), fill=(242, 196, 88, 255))            # ouro
    d.polygon(dia(W * 0.30), fill=(120, 74, 14, 255))             # filete
    d.polygon(dia(W * 0.27), fill=mid)                             # gema
    d.polygon([(c, c - W * 0.27), (c + W * 0.27, c), (c, c)], fill=top)          # faceta de cima (clara)
    d.polygon([(c, c), (c, c + W * 0.27), (c - W * 0.27, c)], fill=bot)          # faceta de baixo (escura)
    d.polygon([(c - W * 0.06, c - W * 0.16), (c + W * 0.02, c - W * 0.2), (c - W * 0.02, c - W * 0.08)], fill=(255, 255, 255, 170))   # reflexo
    im.resize((S, S), Image.LANCZOS).save("ui_kit/art/%s.png" % name)
gem((120, 255, 150, 255), (36, 196, 92, 255), (10, 110, 52, 255), (60, 255, 120, 120), "fr_ico_online")
gem((200, 206, 214, 255), (128, 134, 146, 255), (70, 74, 84, 255), None, "fr_ico_offline")
gem((200, 206, 214, 255), (128, 134, 146, 255), (70, 74, 84, 255), None, "fr_ico_dot_off")
