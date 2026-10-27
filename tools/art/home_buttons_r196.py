# R196 · placas da Home do celular a partir da arte do dono: WhatsApp e BAIXAR O APP (recorte, 1000x270 as duas) e o
# brilho NEON ROXO do PASSE (silhueta da placa desfocada, em roxo; o jogo acende e apaga).
# Uso: python3 tools/art/home_buttons_r196.py <whatsapp.png> <app.png>
import sys
from PIL import Image, ImageFilter
def plate(src, dst, w=1000, h=270):
    im = Image.open(src).convert("RGBA")
    bb = im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    im = im.crop(bb)
    im = im.resize((w, h), Image.LANCZOS)   # as duas do MESMO tamanho
    im.save(dst, optimize=True)
    print(dst, im.size)
plate(sys.argv[1], "ui_kit/art/whatsapp_plate.png")
plate(sys.argv[2], "ui_kit/art/app_plate.png")
# brilho do passe: 1/4 da placa (509x126) + margem de 40 px, silhueta engordada e desfocada
p = Image.open("economy/art/pass_button_plate.png").convert("RGBA")
q = 4; pad = 40
a = p.getchannel("A").resize((p.width // q, p.height // q), Image.LANCZOS).point(lambda v: 255 if v > 60 else 0)
c = Image.new("L", (a.width + pad * 2, a.height + pad * 2), 0); c.paste(a, (pad, pad))
c = c.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(12))
g = Image.new("RGBA", c.size, (190, 110, 255, 0)); g.putalpha(c)
g.save("economy/art/pass_button_glow.png", optimize=True)
print("glow", g.size, "pad", pad, "q", q)
