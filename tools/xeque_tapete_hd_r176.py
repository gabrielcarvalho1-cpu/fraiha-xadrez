#!/usr/bin/env python3
"""R176.8 · medalhão do centro da mesa do XEQUE sem serrilhado: os anéis da arte (pixel art 242 px) são refeitos como
círculos perfeitos (perfil de cor medido no próprio tapete, mediana por raio), os 8 raios finos e a coroa voltam por
cima; desenhado 4x maior com antisserrilhado. Saída: xeque/art/mesa/tapete_hd.png (968 px, RGBA)."""
import numpy as np, cv2
from PIL import Image

SRC = "xeque/art/mesa/tapete.png"
OUT = "xeque/art/mesa/tapete_hd.png"
UP = 4          # saída
SS = 3          # superamostragem

def main():
    t = np.array(Image.open(SRC).convert("RGBA")).astype(np.float32)
    h, w = t.shape[:2]
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    yy, xx = np.mgrid[0:h, 0:w]
    rr = np.hypot(xx - cx, yy - cy)
    ang = np.degrees(np.arctan2(yy - cy, xx - cx)) % 45.0
    off_spoke = (ang > 6) & (ang < 39)
    R = w / 2.0
    step = 0.25
    radii = np.arange(0, R + 1, step)
    prof = np.zeros((len(radii), 4), np.float32)
    for i, r in enumerate(radii):
        m = (np.abs(rr - r) < 0.75) & off_spoke & (t[..., 3] > 8)
        if m.sum() < 3: m = (np.abs(rr - r) < 1.5) & (t[..., 3] > 8)
        prof[i] = np.median(t[m], axis=0) if m.sum() else (0, 0, 0, 0)
    # miolo liso: dentro do anel interno o perfil é o vermelho logo antes dele (a coroa não vira "disco")
    j = int(43 / step)
    prof[:j] = prof[j]
    # suaviza só um pouquinho o perfil (as bordas dos anéis continuam definidas)
    k = np.array([0.25, 0.5, 0.25])
    for c in range(4): prof[:, c] = np.convolve(np.pad(prof[:, c], 1, mode="edge"), k, mode="valid")
    N = w * UP * SS
    s = w / N
    gy, gx = np.mgrid[0:N, 0:N].astype(np.float32)
    r_src = np.hypot((gx + 0.5) * s - 0.5 - cx, (gy + 0.5) * s - 0.5 - cy)
    idx = np.clip(r_src / step, 0, len(radii) - 1)
    i0 = np.floor(idx).astype(int); i1 = np.minimum(i0 + 1, len(radii) - 1); f = (idx - i0)[..., None]
    img = prof[i0] * (1 - f) + prof[i1] * f
    edge = np.clip((R - 0.6 - r_src) / (s * 1.5), 0, 1)       # borda externa lisa
    img[..., 3] = np.minimum(img[..., 3], 255 * edge)
    # 8 raios finos (cor medida na arte)
    sp = t[(np.abs(xx - cx) < 1) & (rr > 55) & (rr < 82)]
    sp_col = np.median(sp, axis=0)[:3] if len(sp) else np.array([150, 40, 60], np.float32)
    a_src = np.degrees(np.arctan2((gy + 0.5) * s - 0.5 - cy, (gx + 0.5) * s - 0.5 - cx))
    d_ang = np.abs(((a_src + 22.5) % 45.0) - 22.5)
    dist = np.radians(d_ang) * r_src
    spoke = np.clip(1.0 - (dist - 0.7) / (s * 1.5), 0, 1) * ((r_src > 53) & (r_src < 84))
    img[..., :3] = img[..., :3] * (1 - spoke[..., None] * 0.85) + sp_col * spoke[..., None] * 0.85
    big = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA").resize((w * UP, w * UP), Image.LANCZOS)
    # coroa: da arte original (só o miolo), ampliada suave
    crown = Image.fromarray(t.astype(np.uint8), "RGBA")
    cm = np.array(crown)
    inner = (rr < 41)
    r_, g_, b_ = (cm[..., i].astype(np.float32) for i in range(3))
    crown_px = inner & (g_ > r_ * 0.45) & (r_ > b_ + 30) & (cm[..., 3] > 8)
    crown_px = cv2.morphologyEx(crown_px.astype(np.uint8), cv2.MORPH_OPEN, np.ones((2, 2), np.uint8)) > 0
    cm[..., 3] = np.where(crown_px, 255, 0).astype(np.uint8)
    # contorno da coroa liso (máscara ampliada e re-limiarizada) e cor espalhada para fora antes de ampliar
    W2 = w * UP
    am = cv2.resize(crown_px.astype(np.float32), (W2, W2), interpolation=cv2.INTER_CUBIC)
    am = cv2.GaussianBlur(am, (0, 0), UP * 1.0)
    alpha = np.clip((am - 0.5) / 0.12 + 0.5, 0, 1)
    rgb = cm[..., :3].copy()
    known = crown_px.copy()
    for _ in range(4):
        dil = cv2.dilate(rgb * known[..., None], np.ones((3, 3), np.uint8))
        cnt = cv2.dilate(known.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
        rgb = np.where(known[..., None], rgb, dil)
        known = cnt
    crgb = cv2.resize(rgb, (W2, W2), interpolation=cv2.INTER_NEAREST)
    crgb = cv2.GaussianBlur(crgb, (0, 0), UP * 0.6)
    cimg = Image.fromarray(np.dstack([crgb, (alpha * 255).astype(np.uint8)]), "RGBA")
    big.alpha_composite(cimg)
    big.save(OUT)
    print("ok", big.size)

if __name__ == "__main__":
    main()
