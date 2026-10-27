# R198 · CHAT GLOBAL (PC) com a ARTE do dono: painel sem os textos que mudam (abas, "N pessoas no chat",
# "Ninguém escreveu...", "Escreva para todos...") + aba acesa/apagada sem texto (as flores-de-lis ficam).
# Uso: python3 tools/art/chat_r198.py <referencia.png>
import sys, numpy as np
from PIL import Image
src = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).astype(np.float32)
OUT = "ui_kit/pages/chat_r198/"
def wipe(a, x0, y0, x1, y1, cx, w=4):
    a[y0:y1, x0:x1] = a[y0:y1, cx:cx + w].mean(axis=1, keepdims=True)
def lerp_wipe(a, x0, y0, x1, y1, lx, rx, w=3):
    L = a[y0:y1, lx:lx + w].mean(axis=1, keepdims=True); R = a[y0:y1, rx:rx + w].mean(axis=1, keepdims=True)
    t = np.linspace(0, 1, x1 - x0)[None, :, None]
    a[y0:y1, x0:x1] = L * (1 - t) + R * t
def save(a, name):
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(OUT + name, optimize=True)
    print(name, a.shape[1], a.shape[0])
p = src.copy()
wipe(p, 192, 196, 1090, 240, 1300)        # "1 pessoa no chat agora · toque numa mensagem..."
p[553:599, 134:912] = src[505:551, 134:912]   # "Ninguém escreveu..." → o fundo logo acima
wipe(p, 222, 636, 560, 686, 760)          # "Escreva para todos..."
save(p, "panel.png")
on = src[94:190, 160:704].copy(); wipe(on, 292 - 160, 18, 590 - 160, 78, 286 - 160); save(on, "tab_on.png")
off = src[94:190, 712:1268].copy(); wipe(off, 798 - 712, 18, 1198 - 712, 78, 794 - 712); save(off, "tab_off.png")
