"""R159 · arte em pé do HUD sem cortes: a moldura do tabuleiro some suave em cima e embaixo (alfa),
sem os cartões desenhados na arte (os cartões de verdade ficam por cima, sobre o fundo limpo)."""
from PIL import Image
import numpy as np
a = np.array(Image.open('ranked/art/mob_hud_p_top.png').convert('RGBA')).astype(np.float32)
h = a.shape[0]
y = np.arange(h, dtype=np.float32)
def ramp(v, a0, a1): return np.clip((v - a0) / (a1 - a0), 0, 1)
alpha = ramp(y, 10, 150) * (1 - ramp(y, 948, 992))
alpha = alpha * alpha * (3 - 2 * alpha)   # smoothstep
al = np.repeat(alpha[:, None], a.shape[1], axis=1)
# sem os cartões desenhados na arte: o cartão limpo do jogo fica por cima e pode ser mais estreito que o da arte
from PIL import ImageFilter
m = Image.new('L', (a.shape[1], h), 0)
from PIL import ImageDraw
d = ImageDraw.Draw(m)
for r in [(128, 64, 842, 182), (86, 962, 858, 1082)]:
    d.rectangle((r[0] - 6, r[1] - 6, r[2] + 6, r[3] + 6), fill=255)
m = np.array(m.filter(ImageFilter.GaussianBlur(8))).astype(np.float32) / 255.0
al = al * (1 - m)
a[..., 3] = 255 * al
Image.fromarray(a.astype(np.uint8)).save('ranked/art/mob_hud_p_soft.png', optimize=True)
