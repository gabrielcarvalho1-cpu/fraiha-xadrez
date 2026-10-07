"""R47 · Home v8 = as DUAS ARTES DE REFERÊNCIA aprovadas pelo dono (PC 1672x941 · celular 854x1842).

Mesma regra da v7 (tools/home_ref_v7.py): a referência vira o fundo inteiro — cenário, logo, molduras,
botões com ícones, setas e selos NOVO — e só o que é VIVO no jogo sai da arte, para o Godot desenhar
por cima com o estado real do jogador e com a fonte do jogo (nítida em qualquer tela, R44.1):
  • placa CLUB: texto e seta (o jogo escreve ativo/inativo); quadrados de som / tela cheia: os ícones;
  • cartão de perfil: retrato, nome, liga/PL (ficam moldura, coroa, barra vazia, escudo da Madeira e citação);
  • placa da conta (PC): textos; no medalhão volta o ícone de convidado da arte v7 (o avatar vivo cobre);
  • textos de TODOS os botões do menu (ficam moldura, ícone, seta e NOVO);
  • celular: textos da barra de baixo (INÍCIO · AMIGOS · MINHA CONTA · MAIS); os ícones ficam.
Entradas: tools/home_ref/home_referencia_r47_pc.png e home_referencia_r47_mobile.png (arquivos do dono,
          sem alteração); ui_v022/assets/home_forest_v7_wide.png (laterais do modo janela, R43) e
          home_forest_v7.png (medalhão de convidado).
Saídas:   ui_v022/assets/home_forest_v8.png, home_forest_v8_wide.png, home_mobile_v8.png
Uso: python3 tools/home_ref_v8.py [raiz_do_repo]"""
import sys
import numpy as np
import cv2
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
A = ROOT + '/ui_v022/assets/'


def load(p):
    return np.array(Image.open(p).convert('RGB'))


def fill_dark(img, mask, sigma=14, known_max=58, seed=47):
    """Recompõe o fundo ESCURO sob a máscara: média gaussiana só dos pixels escuros em volta, + grão fino."""
    f = img.astype(np.float64)
    lum = f.mean(axis=2)
    known = ((mask == 0) & (lum < known_max)).astype(np.float64)
    num = np.stack([cv2.GaussianBlur(f[..., c] * known, (0, 0), sigma) for c in range(3)], axis=2)
    den = cv2.GaussianBlur(known, (0, 0), sigma)[..., None] + 1e-6
    rng = np.random.default_rng(seed)
    filled = np.clip(num / den + rng.normal(0, 1.6, f.shape[:2])[..., None], 0, 255)
    a = cv2.GaussianBlur((mask > 0).astype(np.float64), (0, 0), 1.2)
    a = np.where(mask > 0, 1.0, a)[..., None]
    return (f * (1 - a) + filled * a).astype(np.uint8)


def rect_mask(shape, box):
    m = np.zeros(shape[:2], np.uint8)
    cv2.rectangle(m, (box[0], box[1]), (box[2], box[3]), 255, -1)
    return m


def fill_rows(img, box, lum_max=60, seed=7):
    """Cada fileira recebe a mediana dos pixels ESCUROS dela mesma (fundo liso da placa com o degradê
    vertical da arte) + grão fino; as pontas se misturam suavemente."""
    x0, y0, x1, y1 = box
    res = img.copy()
    rng = np.random.default_rng(seed)
    meds = []
    for y in range(y0, y1 + 1):
        row = img[y, x0:x1 + 1].astype(np.float64)
        dark = row[row.mean(axis=1) < lum_max]
        meds.append(np.median(dark, axis=0) if len(dark) >= 4 else None)
    last = next(m for m in meds if m is not None)
    for i in range(len(meds)):
        if meds[i] is None: meds[i] = last
        last = meds[i]
    meds = cv2.GaussianBlur(np.array(meds)[:, None, :], (1, 5), 0)[:, 0, :]
    for y in range(y0, y1 + 1):
        row = img[y, x0:x1 + 1].astype(np.float64)
        fill = meds[y - y0] + rng.normal(0, 1.4, (x1 - x0 + 1, 1))
        a = np.ones(x1 - x0 + 1)
        e = min(6, (x1 - x0) // 4)
        a[:e] = np.linspace(0.2, 1, e); a[-e:] = np.linspace(1, 0.2, e)
        res[y, x0:x1 + 1] = np.clip(row * (1 - a[:, None]) + fill * a[:, None], 0, 255).astype(np.uint8)
    return res


def erase_text(img, boxes, thr=22, grow=2, blur=21):
    """Texto claro sobre o fundo do botão: pixels mais claros que o fundo local (mediana) dentro de cada
    caixa saem por inpaint; a mancha é suavizada só onde havia texto (como tools/home_r441_text.py)."""
    bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    lum = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
    bgl = cv2.cvtColor(cv2.medianBlur(bgr, blur), cv2.COLOR_BGR2GRAY).astype(np.float32)
    mask = np.zeros(lum.shape, np.uint8)
    for (x0, y0, x1, y1) in boxes:
        mask[y0:y1, x0:x1] = ((lum[y0:y1, x0:x1] - bgl[y0:y1, x0:x1]) > thr).astype(np.uint8)
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=grow)
    clip = np.zeros_like(mask)
    for (x0, y0, x1, y1) in boxes: clip[y0:y1, x0:x1] = 1
    mask &= clip   # a dilatação nunca passa da caixa (bordas douradas, ícones e NOVO ficam intactos)
    out = cv2.inpaint(bgr, mask * 255, 5, cv2.INPAINT_TELEA)
    soft = cv2.GaussianBlur(out, (0, 0), 1.6)
    mf = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 1.5)[..., None]
    out = (out * (1 - mf) + soft * mf).astype(np.uint8)
    return cv2.cvtColor(out, cv2.COLOR_BGR2RGB)


def paste_disc(dst, src, center, r, feather=2.5):
    yy, xx = np.mgrid[0:dst.shape[0], 0:dst.shape[1]]
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    a = np.clip((r - d) / feather, 0, 1)[..., None]
    return (dst * (1 - a) + src * a).astype(np.uint8)


# =============================== PC ===============================
ref = load(ROOT + '/tools/home_ref/home_referencia_r47_pc.png')
v7 = load(A + 'home_forest_v7.png')
assert ref.shape == v7.shape == (941, 1672, 3), ref.shape
out = ref.copy()
# 1. placa CLUB (texto + seta) e ícones de som / tela cheia
for box in [(95, 22, 342, 72), (369, 23, 420, 72), (439, 23, 489, 72)]:
    out = fill_rows(out, box)
# 2. cartão de perfil: retrato (dentro da moldura dourada da arte), nome, liga/PL
out = fill_dark(out, rect_mask(out.shape, (1257, 67, 1341, 149)), 30)
out = fill_dark(out, rect_mask(out.shape, (1387, 50, 1540, 89)))
out = fill_dark(out, rect_mask(out.shape, (1356, 90, 1540, 113)))
# 3. placa da conta: textos; medalhão de convidado da arte v7 (mesma posição, registro ~identidade)
out = fill_dark(out, rect_mask(out.shape, (126, 856, 302, 910)), 10)
out = paste_disc(out, v7, (75, 881), 33)
# 4. textos dos botões do menu (PC_TEXT = mesmas caixas usadas pelo main_hub.gd para escrever)
PC_TEXT = [(694, 350, 1002, 401), (694, 423, 1002, 475), (700, 498, 1002, 555),   # 3 linhas grandes
           (655, 607, 761, 645), (890, 607, 975, 645),                             # MARCHA REAL · XEQUE
           (655, 669, 800, 706), (890, 669, 1038, 706),                            # LIGAS · HISTÓRICO
           (660, 731, 800, 768), (890, 731, 1038, 768),                            # AMIGOS · CONHEÇA
           (665, 811, 797, 849), (895, 811, 990, 849)]                             # CONFIGURAÇÕES · SAIR
out = erase_text(out, PC_TEXT)
Image.fromarray(out).save(A + 'home_forest_v8.png', optimize=True)

# modo janela (R43): as laterais completadas da v7 + o meio novo, emenda suave de 40 px
wide = load(A + 'home_forest_v7_wide.png').astype(np.float32)
PAD, B = 84, 40
w = wide.copy(); w[:, PAD:PAD + 1672] = out
for k in range(B):
    t = k / (B - 1); t = t * t * (3 - 2 * t)
    xl, xr = PAD + k, PAD + 1671 - k
    w[:, xl] = wide[:, xl] * (1 - t) + out[:, k] * t
    w[:, xr] = wide[:, xr] * (1 - t) + out[:, 1671 - k] * t
w = np.clip(w, 0, 255).astype(np.uint8)
Image.fromarray(w).save(A + 'home_forest_v8_wide.png', optimize=True)

# ============================= CELULAR =============================
mob = load(ROOT + '/tools/home_ref/home_referencia_r47_mobile.png')
assert mob.shape == (1842, 854, 3), mob.shape
mo = mob.copy()
# placa CLUB (texto + seta) e ícone do som
mo = fill_rows(mo, (118, 56, 368, 107))
mo = fill_rows(mo, (738, 56, 806, 112))
# cartão de perfil
mo = fill_dark(mo, rect_mask(mo.shape, (150, 524, 266, 642)), 30)
mo = fill_dark(mo, rect_mask(mo.shape, (340, 516, 560, 560)))
mo = fill_dark(mo, rect_mask(mo.shape, (292, 561, 560, 593)))
MOB_TEXT = [(272, 758, 650, 840), (272, 895, 652, 970), (272, 1018, 660, 1090),    # RANQUEADO · ONLINE · COMPUTADOR
            (208, 1178, 334, 1217), (530, 1178, 627, 1217),                       # MARCHA REAL · XEQUE
            (218, 1266, 400, 1304), (534, 1266, 666, 1304),                       # LIGAS · HISTÓRICO
            (78, 1768, 168, 1806), (268, 1768, 372, 1806), (448, 1768, 610, 1806), (696, 1768, 770, 1806)]   # barra
mo = erase_text(mo, MOB_TEXT)
Image.fromarray(mo).save(A + 'home_mobile_v8.png', optimize=True)
print('ok')
