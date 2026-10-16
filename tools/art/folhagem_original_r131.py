#!/usr/bin/env python3
"""R131 · a folhagem do cenário da partida (Madeira) tinha ficado AZUL: o R113 (verde_para_azul.py) era para trocar só
o verde dos PAINÉIS/BOTÕES, mas as árvores verde-azuladas caíram na mesma faixa de cor. Aqui: cenário = arte ORIGINAL
(antes do R113) e só dentro dos painéis/botões fica a versão azul aprovada.
Retângulos = ranked/board_skin.gd (PC 1672x941 e celular 888x1772). Uso: python3 tools/art/folhagem_original_r131.py"""
import os, subprocess, io
from PIL import Image
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
BEFORE = "0ac500c^"   # commit anterior ao R113
PAD = 0   # contorno exato do painel (margem trazia de volta folhagem azul em volta)
PC = [(18, 17, 225, 60), (1085, 10, 580, 68), (1158, 122, 488, 168), (1158, 122 + 566, 488, 168),
      (1158, 305, 488, 370)]   # DESISTIR é vermelho (o R113 não mexeu nele): fica a arte original
MOB = [(20, 20, 268, 80), (640, 20, 80, 75), (728, 20, 72, 75), (806, 20, 66, 75), (12, 272, 864, 134),
       (12, 272 + 1042, 864, 134), (25, 1465, 837, 80), (278, 1570, 74, 75), (362, 1570, 74, 75), (446, 1570, 164, 75)]
LAND = [(535, 18, 610, 92), (535, 818, 610, 92)]   # celular deitado (mob_hud_l_art): as 2 barras de jogador
PORT = [(125, 75, 710, 100), (85, 972, 765, 102)]   # celular em pé (mob_hud_p_top): as 2 placas de jogador
MOB_BOT = MOB[:7]   # contra o bot: sem microfone/fone/voz (ali é folhagem)
for name, rects in [("board_pc", PC), ("board_pc_bot", PC), ("board_mob", MOB), ("board_mob_bot", MOB_BOT), ("mob_hud_l_art", LAND), ("mob_hud_p_top", PORT), ("mob_hud_fill", [])]:   # fill = só cenário
    path = os.path.join(ROOT, "ranked/art", name + ".png")
    blue = Image.open(path).convert("RGB")
    raw = subprocess.check_output(["git", "-C", ROOT, "show", f"{BEFORE}:ranked/art/{name}.png"])
    out = Image.open(io.BytesIO(raw)).convert("RGB")
    for x, y, w, h in rects:
        box = (max(0, x - PAD), max(0, y - PAD), min(out.width, x + w + PAD), min(out.height, y + h + PAD))
        out.paste(blue.crop(box), box[:2])
    out.save(path, optimize=True)
    print(name, out.size)
