"""R87 · Celular, tabuleiro de madeira: as 64 casas pintadas na arte (presentation_v019/forest_wide.png)
recortadas uma a uma (1 px para dentro, sem as emendas/riscos) num atlas 8x8 de casas quadradas.
O jogo desenha cada casa exatamente na grade jogável, então destaques e casas ficam alinhados."""
import os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
art = Image.open(os.path.join(ROOT, "presentation_v019/forest_wide.png")).convert("RGB")
XS = [522, 592, 662, 732, 801, 872, 941, 1012, 1083]   # bordas medidas na arte (troca de cor das casas)
YS = [172, 241, 310, 378, 447, 514, 582, 649, 718]
C = 80
out = Image.new("RGB", (C * 8, C * 8))
for r in range(8):
    for c in range(8):
        box = (XS[c] + 2, YS[r] + 2, XS[c + 1] - 2, YS[r + 1] - 2)
        out.paste(art.crop(box).resize((C, C), Image.LANCZOS), (c * C, r * C))
out.save(os.path.join(ROOT, "visual_v018/casas_madeira.png"))
print("ok", out.size)
