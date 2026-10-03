"""R36 · Home v7 = a ARTE DE REFERÊNCIA aprovada pelo dono (1672x941, mesmo tamanho do DESIGN).

A referência é uma captura "ideal" da própria Home (com uma conta Club logada). Ela vira o fundo
inteiro — menu com pilares e tochas, 11 linhas com textos e selos NOVO, logo, cenário — e só o que é
VIVO no jogo é apagado da arte, para o Godot desenhar por cima com o estado real do jogador:
  • canto superior esquerdo: a placa CLUB e os quadrados de som / tela cheia ficam; saem só os
    textos, o selo ✓ e os ícones (o jogo desenha o estado real por cima);
  • cartão de perfil: retrato + moldura Club, nome e selo ao lado, liga/PL; ficam a moldura do
    cartão, a coroa à esquerda do nome, a barra de PL (vazia), a legenda, a citação e o escudo;
    o lugar do retrato ganha uma moldura dourada simples (o retrato vivo encaixa nela);
  • placa da conta (embaixo, à esquerda): só os textos saem (o ícone de convidado e a seta ficam).
Entrada: tools/home_ref/home_referencia_r36.png (arquivo enviado pelo dono, sem alteração).
Saída:   ui_v022/assets/home_forest_v7.png"""
import os
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
REF = os.path.join(ROOT, "tools/home_ref/home_referencia_r36.png")
OLD = os.path.join(ROOT, "ui_v022/assets/home_forest_v6.png")
OUT = os.path.join(ROOT, "ui_v022/assets/home_forest_v7.png")

ref = np.array(Image.open(REF).convert("RGB"))
old = np.array(Image.open(OLD).convert("RGB"))
assert ref.shape == old.shape == (941, 1672, 3), ref.shape
out = ref.copy()


def inpaint(img, mask, r=4):
    return cv2.cvtColor(cv2.inpaint(cv2.cvtColor(img, cv2.COLOR_RGB2BGR), mask, r, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)


def bright_mask(img, box, thr, grow=2):
    """Pixels de texto/ícone (claros ou dourados) dentro da caixa, dilatados."""
    x0, y0, x1, y1 = box
    sub = img[y0:y1, x0:x1].astype(np.int32)
    lum = sub.mean(axis=2)
    m = np.zeros(img.shape[:2], np.uint8)
    m[y0:y1, x0:x1] = (lum > thr).astype(np.uint8) * 255
    if grow: m = cv2.dilate(m, np.ones((grow * 2 + 1, grow * 2 + 1), np.uint8))
    return m


# ---------- 2. cartão de perfil ----------
def fill_dark(img, mask, sigma=14, known_max=58):
    """Recompõe o fundo ESCURO do painel sob a máscara: média gaussiana só dos pixels escuros em volta
    (o dourado da moldura e os textos não entram), mais o grão fino do próprio painel."""
    f = img.astype(np.float64)
    lum = f.mean(axis=2)
    known = ((mask == 0) & (lum < known_max)).astype(np.float64)
    k = (0, 0)
    num = np.stack([cv2.GaussianBlur(f[..., c] * known, k, sigma) for c in range(3)], axis=2)
    den = cv2.GaussianBlur(known, k, sigma)[..., None] + 1e-6
    bg = num / den
    rng = np.random.default_rng(36)
    grain = rng.normal(0, 1.6, bg.shape[:2])[..., None]
    filled = np.clip(bg + grain, 0, 255)
    # borda suave (sem retângulo visível); onde a arte tem texto/ícone claro, troca inteira
    a = cv2.GaussianBlur((mask > 0).astype(np.float64), (0, 0), 2.5)
    a = np.where((mask > 0) & (lum >= known_max), 1.0, np.where(mask > 0, np.maximum(a, 0.0), a * 0))
    a = a[..., None]
    return (f * (1 - a) + filled * a).astype(np.uint8)


# ---------- 1. canto superior esquerdo: a placa CLUB e os quadrados de som/tela cheia FICAM ----------
# (pedido do dono: o botão do Club com o visual da referência). Só saem os textos e o selo ✓ da placa
# e os ícones dos quadrados — o jogo desenha por cima o estado real (ativo/inativo, som, tela cheia).
def fill_rows(img, box, lum_max=60):
    """Cada fileira recebe a mediana dos pixels ESCUROS dela mesma (o fundo liso da placa, com o
    degradê vertical da arte), mais um grão fino; as colunas das pontas se misturam suavemente."""
    x0, y0, x1, y1 = box
    res = img.copy()
    rng = np.random.default_rng(7)
    meds = []
    for y in range(y0, y1 + 1):
        row = img[y, x0:x1 + 1].astype(np.float64)
        dark = row[row.mean(axis=1) < lum_max]
        meds.append(np.median(dark, axis=0) if len(dark) >= 4 else None)
    last = next(m for m in meds if m is not None)
    for i in range(len(meds)):
        if meds[i] is None: meds[i] = last
        last = meds[i]
    meds = cv2.GaussianBlur(np.array(meds)[:, None, :], (1, 5), 0)[:, 0, :]   # degradê sem degraus
    for y in range(y0, y1 + 1):
        row = img[y, x0:x1 + 1].astype(np.float64)
        med = meds[y - y0]
        fill = med + rng.normal(0, 1.4, (x1 - x0 + 1, 1))
        a = np.ones(x1 - x0 + 1)
        e = min(6, (x1 - x0) // 4)
        a[:e] = np.linspace(0.2, 1, e); a[-e:] = np.linspace(1, 0.2, e)
        res[y, x0:x1 + 1] = np.clip(row * (1 - a[:, None]) + fill * a[:, None], 0, 255).astype(np.uint8)
    return res


for box in [(95, 22, 342, 72), (369, 23, 420, 72), (439, 23, 489, 72)]:
    out = fill_rows(out, box)

# 2a. retrato + moldura Club (medalhão sobre a borda de cima): o painel verde é recomposto
m = np.zeros(out.shape[:2], np.uint8)
cv2.rectangle(m, (1236, 41), (1356, 172), 255, -1)
out = fill_dark(out, m, 34)
# acima da borda (céu atrás do medalhão): cada fileira liga a cor da esquerda à da direita
for y in range(14, 35):
    a = ref[y, 1252:1256].astype(np.float64).mean(0)
    b = ref[y, 1340:1344].astype(np.float64).mean(0)
    for x in range(1256, 1340):
        t = (x - 1256) / (1340 - 1256)
        out[y, x] = (a * (1 - t) + b * t).astype(np.uint8)
# a borda dourada de cima (fileiras 35–40), copiada de um trecho limpo da mesma borda
out[35:41, 1252:1362] = ref[35:41, 1490:1600]
# moldura dourada simples no lugar do retrato (o retrato vivo encaixa dentro dela)
GOLD = (222, 178, 88)
cv2.rectangle(out, (1250, 60), (1343, 160), GOLD, 2)
cv2.rectangle(out, (1254, 64), (1339, 156), (120, 92, 40), 1)
for c in [(1250, 60), (1343, 60), (1250, 160), (1343, 160)]:
    pts = np.array([[c[0], c[1] - 5], [c[0] + 5, c[1]], [c[0], c[1] + 5], [c[0] - 5, c[1]]], np.int32)
    cv2.fillPoly(out, [pts], (240, 207, 122))
# 2b. nome + selo à direita do nome (a coroa da esquerda fica)
m = np.zeros(out.shape[:2], np.uint8); cv2.rectangle(m, (1388, 48), (1508, 90), 255, -1)
out = fill_dark(out, m)
# 2c. liga / PL
m = np.zeros(out.shape[:2], np.uint8); cv2.rectangle(m, (1356, 90), (1522, 113), 255, -1)
out = fill_dark(out, m)

# ---------- 3. placa da conta: só os textos ----------
m = np.zeros(out.shape[:2], np.uint8); cv2.rectangle(m, (126, 856), (302, 908), 255, -1)
out = fill_dark(out, m, 10)

# ---------- 4. SAIR: fica só a palavra (R37.2, pedido do dono): some "Até a próxima partida!" ----------
x0, x1 = 690, 868
for y in range(864, 884):
    L = out[y, x0 - 3:x0].astype(np.float64).mean(axis=0)
    R = out[y, x1:x1 + 3].astype(np.float64).mean(axis=0)
    t = np.linspace(0, 1, x1 - x0)[:, None]
    out[y, x0:x1] = (L * (1 - t) + R * t).astype(np.uint8)

Image.fromarray(out).save(OUT, optimize=True)
print("ok", OUT)
