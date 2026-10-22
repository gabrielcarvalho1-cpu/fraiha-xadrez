#!/usr/bin/env python3
"""R176.8 · ícones do CONHEÇA O FRAIHA a partir da referência enviada pelo dono (6 placas com ícone à esquerda):
recorta cada ícone, tira o fundo azul/escuro da placa (fica só o desenho, com borda suave) e salva 256 px.
Uso: python3 tools/about_icons_r176.py <referencia.png>"""
import sys
import numpy as np, cv2
from PIL import Image

NAMES = ["projeto", "como", "ligas", "modos", "perso", "comunidade"]
CYS = [135, 330, 527, 722, 917, 1113]
OUT = "ui_kit/pages/about_ico_%s.png"
SIDE = 256

def main(src):
    im = np.array(Image.open(src).convert("RGB")).astype(np.int32)
    for name, cy in zip(NAMES, CYS):
        c = im[cy - 76:cy + 78, 138:322]
        r, g, b = c[..., 0], c[..., 1], c[..., 2]
        mx = c.max(-1)
        warm = (r - b > 45) & (mx > 95)
        bright = mx > 215
        gem = (b > 125) & (b - r > 55)                              # gemas e fita azuis
        red_green = ((r > 140) & (g < 90)) | ((g > 110) & (r < 90) & (b < 120))   # gemas vermelha/verde da paleta
        border = np.concatenate([c[:, :6].reshape(-1, 3), c[:, -6:].reshape(-1, 3)])
        bg = np.median(border, axis=0)
        far = np.abs(c - bg).sum(-1) > 110                          # fundo da placa (azul ou o oliva da placa ativa)
        core = ((warm | bright | gem | red_green) & far).astype(np.uint8)
        # só o desenho grande do meio (descarta as linhas da placa e respingos)
        n, lab, st, _ = cv2.connectedComponentsWithStats(cv2.dilate(core, np.ones((3, 3), np.uint8)))
        keep = np.zeros_like(core)
        for i in range(1, n):
            x, y, w, h, a = st[i]
            if a > 150 and not (h < 14 and w > 40) and x > 2 and x + w < lab.shape[1] - 2: keep[lab == i] = 1
        core = core & keep
        # buracos (miolo do escudo etc.) entram; contorno escuro (1-2 px) também
        h_, w_ = core.shape
        ff = cv2.dilate(core, np.ones((3, 3), np.uint8)).copy()
        mask = np.zeros((h_ + 2, w_ + 2), np.uint8)
        filled = ff.copy()
        cv2.floodFill(filled, mask, (0, 0), 2)
        inside = (filled != 2).astype(np.uint8)
        full = cv2.dilate(inside, np.ones((3, 3), np.uint8))
        alpha = cv2.GaussianBlur(full.astype(np.float32) * 255, (0, 0), 0.9)
        rgba = np.dstack([c.astype(np.uint8), np.clip(alpha, 0, 255).astype(np.uint8)])
        ys, xs = np.where(full > 0)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        crop = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
        k = (SIDE * 0.94) / max(crop.size)
        crop = crop.resize((max(1, round(crop.width * k)), max(1, round(crop.height * k))), Image.LANCZOS)
        out = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
        out.alpha_composite(crop, ((SIDE - crop.width) // 2, (SIDE - crop.height) // 2))
        out.save(OUT % name)
        print(name, crop.size)

if __name__ == "__main__":
    main(sys.argv[1])
