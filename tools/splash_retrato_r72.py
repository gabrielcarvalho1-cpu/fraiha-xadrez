"""R72 · Tela de carregamento do celular EM PÉ: a arte larga (branding/fraiha_loading_splash_r63.png) recomposta em
1080x2340 — cena (título + rei e dama) no alto, faixa "PREPARANDO O TABULEIRO / barra / Carregando o reino" embaixo,
fundo da própria arte desfocado preenchendo a tela inteira. Gera um JPEG pequeno (vai como data: URI no index.html).
Uso: python3 tools/splash_retrato_r72.py tools/web_release/splash_retrato_r72.jpg  → imprime a caixa da barra (frações da imagem) para o JS."""
import sys
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance

SRC = "branding/fraiha_loading_splash_r63.png"
W, H = 1080, 2340
SCENE = (586, 0, 1086, 712)        # título + peças + começo do chão (arte 1672x941)
BAND = (300, 700, 1372, 900)       # textos + moldura da barra (com chão dos lados, para a emenda sumir)
BAR = (457, 783, 753, 28)          # miolo da barra na arte (x, y, w, h) — o mesmo do PC
SCENE_Y = 300                      # R74: conteúdo centrado na altura; a faixa da barra encosta na cena


def feather_v(img, top, bottom):
    a = np.ones((img.height, img.width), np.float32)
    for i in range(top): a[i, :] *= i / float(top)
    for i in range(bottom): a[img.height - 1 - i, :] *= i / float(bottom)
    return Image.fromarray((a * 255).astype(np.uint8))


def main(out):
    art = Image.open(SRC).convert("RGB")
    scene = art.crop(SCENE)
    s = W / scene.width
    scene = scene.resize((W, int(round(scene.height * s))), Image.LANCZOS)
    # fundo: a própria cena cobrindo a tela, desfocada e escurecida (sem faixas vazias)
    k = H / scene.height
    bg = scene.resize((int(scene.width * k), H), Image.LANCZOS)
    bg = bg.crop(((bg.width - W) // 2, 0, (bg.width - W) // 2 + W, H)).filter(ImageFilter.GaussianBlur(28))
    bg = ImageEnhance.Brightness(bg).enhance(0.42)
    # chão: a parte de baixo da cena (reflexos) espelhada para baixo, suave
    floor = art.crop((SCENE[0], 600, SCENE[2], 712)).resize((W, H - 1500), Image.LANCZOS)
    floor = ImageEnhance.Brightness(floor.filter(ImageFilter.GaussianBlur(6))).enhance(0.32)
    bg.paste(floor, (0, H - floor.height), feather_v(floor, 160, 0))
    bg.paste(scene, (0, SCENE_Y), feather_v(scene, 140, 50))
    BAND_Y = SCENE_Y + scene.height - 60
    band = art.crop(BAND)
    bs = W / band.width
    band = band.resize((W, int(round(band.height * bs))), Image.LANCZOS)
    m = np.array(feather_v(band, 55, 55), np.float32) / 255.0
    side = np.clip(np.minimum(np.arange(W), W - 1 - np.arange(W)) / 70.0, 0, 1)[None, :]
    bg.paste(band, (0, BAND_Y), Image.fromarray((m * side * 255).astype(np.uint8)))
    bx = (BAR[0] - BAND[0]) * bs
    by = BAND_Y + (BAR[1] - BAND[1]) * bs
    box = [bx / W, by / H, BAR[2] * bs / W, BAR[3] * bs / H]
    bg.resize((720, 1560), Image.LANCZOS).save(out, quality=84, optimize=True, progressive=True)
    print("BAR", ",".join("%.5f" % v for v in box))


if __name__ == "__main__":
    main(sys.argv[1])
