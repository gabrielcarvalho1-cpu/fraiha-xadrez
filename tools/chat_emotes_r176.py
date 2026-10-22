#!/usr/bin/env python3
"""R176 · artes do chat/emotes (geradas a partir das artes aprovadas, sem desenhar nada novo):
  1) social/art/chat_box_pc.png  = quadro do CHAT da arte do Ranked (board_pc.png) com o cabeçalho refeito:
     [CHAT] [EMOTES] [SILENCIAR] [DENUNCIAR] [—]  (as molduras são a mesma moldura da arte, esticada em 3 partes).
     Usado por cima das duas artes (Ranked/Casual e contra o computador, cujo quadro é vazio);
     chat_box_pc_bot.png = o mesmo sem a moldura de DENUNCIAR (contra o computador não há denúncia).
  2) social/art/emote_banner.png = faixa de referência do dono (troféu + "VOCÊ / BOA PARTIDA!") sem o texto e sem o
     troféu: o jogo escreve o nome e o emote e põe o ícone animado no medalhão.
Uso: python3 tools/chat_emotes_r176.py <referencia_faixa.png>
"""
import sys
import numpy as np
from PIL import Image
import cv2

ART = "ranked/art/board_pc.png"
BOX = (1158, 305, 1646, 675)
FRAME = (1313, 321, 1429, 359)
NEW = {"emotes": (1266, 92), "mute": (1364, 100), "report": (1470, 102)}   # x, largura (px da arte)


def three_slice(src, w, edge=14):
    h = src.height
    out = Image.new("RGBA", (w, h))
    out.paste(src.crop((0, 0, edge, h)), (0, 0))
    out.paste(src.crop((src.width - edge, 0, src.width, h)), (w - edge, 0))
    out.paste(src.crop((edge, 0, src.width - edge, h)).resize((w - 2 * edge, h), Image.LANCZOS), (edge, 0))
    return out


def chat_box(skip=(), out="social/art/chat_box_pc.png"):
    art = Image.open(ART).convert("RGBA")
    box = art.crop(BOX)
    ox, oy = BOX[0], BOX[1]
    col = art.crop((1300, 317, 1301, 363))
    for x in range(1300, 1577):
        box.paste(col, (x - ox, 317 - oy))
    frame = art.crop(FRAME)
    for key, (x, w) in NEW.items():
        if key in skip:
            continue
        f = three_slice(frame, w)
        box.alpha_composite(f, (x - ox, FRAME[1] - oy))
    box.save(out)


def banner(ref_path):
    cx, cy, r = 292, 579, 156
    im = np.array(Image.open(ref_path).convert("RGBA"))
    rgb = cv2.cvtColor(im[:, :, :3], cv2.COLOR_RGB2BGR)
    mask = np.zeros(rgb.shape[:2], np.uint8)
    cv2.rectangle(mask, (752, 452), (975, 548), 255, -1)
    cv2.rectangle(mask, (845, 425), (915, 470), 255, -1)   # losango pequeno acima do nome
    cv2.rectangle(mask, (488, 550), (1335, 695), 255, -1)
    out = cv2.inpaint(rgb, mask, 11, cv2.INPAINT_TELEA)
    # filete dourado do nome: sai inteiro (o jogo redesenha os dois pedaços em volta do nome, do tamanho do nome)
    y0, y1 = 492, 522
    top = out[y0 - 2].astype(float)
    bot = out[y1 + 2].astype(float)
    for y in range(y0, y1 + 1):
        t = (y - y0) / (y1 - y0)
        out[y, 505:1250] = (top * (1 - t) + bot * t)[505:1250].astype(np.uint8)
    yy, xx = np.mgrid[0:out.shape[0], 0:out.shape[1]]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    t = np.clip(d / r, 0, 1)[..., None]
    grad = np.array([112, 50, 16], float) * (1 - t) + np.array([60, 24, 6], float) * t
    glow = np.exp(-(((xx - (cx - 45)) ** 2 + (yy - (cy - 55)) ** 2) / (2 * 75.0 ** 2)))[..., None] * np.array([80, 55, 18], float)
    grad = np.clip(grad + glow * 0.55, 0, 255)
    edge = np.clip((r - d) / 3.0, 0, 1)[..., None]
    out = (grad * edge + out * (1 - edge)).astype(np.uint8)
    cv2.circle(out, (cx, cy), r, (40, 150, 225), 7, cv2.LINE_AA)
    cv2.circle(out, (cx, cy), r - 5, (90, 215, 255), 2, cv2.LINE_AA)
    res = cv2.cvtColor(out, cv2.COLOR_BGR2RGB)
    img = Image.fromarray(np.dstack([res, im[:, :, 3]])).crop((1, 310, 1448, 780))
    img.resize((640, round(img.height * 640 / img.width)), Image.LANCZOS).save("social/art/emote_banner.png")


if __name__ == "__main__":
    chat_box()
    chat_box(skip=("report",), out="social/art/chat_box_pc_bot.png")   # contra o computador não há DENUNCIAR
    if len(sys.argv) > 1:
        banner(sys.argv[1])
    print("ok")
