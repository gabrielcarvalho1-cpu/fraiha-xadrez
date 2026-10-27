# R199 · cartões do JOGAR RANQUEADO / ONLINE (celular): as bordas laterais (trilho dourado) ficavam "desencontradas"
# entre um cartão e o próximo — o pé de cada cartão tinha um enfeite e o trilho mudava de posição. O pé do trilho
# (linhas 300..414, nas duas laterais) vira o mesmo trilho liso do meio do cartão, repetido: tudo emenda reto.
import numpy as np
from PIL import Image
for n in ["rk_card", "rk_card_casual"]:
    p = "ui_kit/mobile/%s.png" % n
    a = np.asarray(Image.open(p).convert("RGBA")).copy()
    for x0, x1 in [(0, 112), (788, 900)]:
        sl = a[222:262, x0:x1].copy()
        for y in range(300, 414, 40):
            h = min(40, 414 - y)
            a[y:y + h, x0:x1] = sl[:h]
    Image.fromarray(a).save(p, optimize=True)
    print(p)
