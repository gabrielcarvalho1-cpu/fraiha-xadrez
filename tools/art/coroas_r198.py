# R198 · painel COROAS (PC) com a ARTE do dono: apaga da imagem só o que muda (saldo, sequência, barra, missões
# feitas, a nota e os últimos ganhos) com inpaint (o fundo azul da arte "preenche" o lugar do texto).
# Uso: python3 tools/art/coroas_r198.py <referencia.png>
import sys, numpy as np, cv2
from PIL import Image
im = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).copy()
OUT = "economy/art/coroas_r198/"
rgb = np.ascontiguousarray(im[:, :, :3][:, :, ::-1])
def erase(x0, y0, x1, y1, thr=62, grow=3, rad=6):
    global rgb
    roi = rgb[y0:y1, x0:x1]
    lum = roi.max(axis=2).astype(np.int32)
    m = (lum > thr).astype(np.uint8) * 255
    m = cv2.dilate(m, np.ones((grow * 2 + 1, grow * 2 + 1), np.uint8))
    full = np.zeros(rgb.shape[:2], np.uint8); full[y0:y1, x0:x1] = m
    rgb = cv2.inpaint(rgb, full, rad, cv2.INPAINT_TELEA)
# ícones dos últimos ganhos (antes de apagar)
for name, (x0, y0, x1, y1) in {"ico_dia": (1135, 543, 1177, 582), "ico_fogo": (1135, 580, 1177, 619), "ico_torneio": (1135, 655, 1177, 696), "badge": (242, 250, 282, 290)}.items():
    Image.fromarray(im[y0:y1, x0:x1]).save(OUT + name + ".png")
erase(362, 78, 900, 168)            # saldo e sequência (o calendário fica: é da entrada do dia)
erase(362, 200, 1000, 230)          # "faltam N dias…"
erase(590, 268, 670, 312, thr=150)  # "0/3" (sobre o laranja: só o texto escuro/claro muito forte)
erase(1128, 385, 1800, 465)         # nota (a arte tinha erros de digitação)
erase(1125, 540, 1795, 700)         # últimos ganhos
out = im.copy(); out[:, :, :3] = rgb[:, :, ::-1]
# barra: miolo vazio da cor da própria barra (o jogo pinta o dourado até o progresso)
bar = out[174:199, 900:960, :3].mean(axis=(1), keepdims=True).astype(np.uint8)
out[174:199, 366:992, :3] = np.repeat(bar, 992 - 366, axis=1)
Image.fromarray(out).save(OUT + "painel.png", optimize=True)
print("ok", out.shape)
