"""R86 · Home do celular em pé: o elo (insígnia da liga) sem o quadrado escuro atrás.
1) escudo_vazio.png: o pedaço do cartão da arte (home_mobile_v8.png) onde fica o escudo de madeira, com o
   escudo apagado (inpaint) — cobre o escudo da arte quando a liga não é Madeira, sem placa lisa.
2) insignias_recorte.png: o atlas das insígnias (cosmetics/assets/badges.png) com o fundo escuro transparente."""
import os
import numpy as np, cv2
from PIL import Image
from scipy import ndimage as ndi
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ui_v022/assets/r86")

art = cv2.imread(os.path.join(ROOT, "ui_v022/assets/home_mobile_v8.png"), cv2.IMREAD_COLOR)
mask = np.zeros(art.shape[:2], np.uint8)
mask[510:652, 614:716] = 255
clean = cv2.inpaint(art, mask, 9, cv2.INPAINT_TELEA)
x, y, w, h = 620, 515, 90, 133
cv2.imwrite(os.path.join(OUT, "escudo_vazio.png"), clean[y:y + h, x:x + w])

atlas = np.asarray(Image.open(os.path.join(ROOT, "cosmetics/assets/badges.png")).convert("RGB")).astype(np.float32)
H, W = atlas.shape[:2]
cw, ch = W // 4, H // 3
alpha = np.zeros((H, W), np.uint8)
for cy in range(3):
    for cx in range(4):
        c = atlas[cy * ch:(cy + 1) * ch, cx * cw:(cx + 1) * cw]
        sm = cv2.GaussianBlur(c, (0, 0), 1.0)
        gx = np.abs(np.diff(sm, axis=1, append=sm[:, -1:])).max(axis=2)
        gy = np.abs(np.diff(sm, axis=0, append=sm[-1:, :])).max(axis=2)
        grad = np.maximum(gx, gy)
        low = grad < 6.0
        lab, n = ndi.label(low)
        border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        bg = np.isin(lab, list(border))
        fg = ~bg
        fg = ndi.binary_opening(fg, iterations=2)
        lab2, n2 = ndi.label(fg)
        if n2 == 0: continue
        sizes = ndi.sum(fg, lab2, range(1, n2 + 1))
        keep = np.zeros_like(fg)
        for i, s in enumerate(sizes):
            if s > 0.02 * fg.size: keep |= lab2 == i + 1
        keep = ndi.binary_fill_holes(keep)
        keep = ndi.binary_erosion(keep, iterations=1)
        a = cv2.GaussianBlur(keep.astype(np.float32) * 255.0, (0, 0), 0.8)
        alpha[cy * ch:(cy + 1) * ch, cx * cw:(cx + 1) * cw] = np.clip(a, 0, 255).astype(np.uint8)
out = Image.fromarray(atlas.astype(np.uint8)).convert("RGBA")
out.putalpha(Image.fromarray(alpha))
out.save(os.path.join(OUT, "insignias_recorte.png"))
print("ok")
