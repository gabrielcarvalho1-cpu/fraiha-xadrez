"""XEQUE e MARCHA REAL · efeitos sonoros dos modos, sintetizados aqui (sem amostras de terceiros,
sem licença a cuidar). Saída: xeque/audio/*.wav e marcha/audio/*.wav (44,1 kHz, mono, 16 bits —
o mesmo formato dos efeitos em audio_v025/). As músicas de fundo (arquivos enviados pelo dono do
projeto) são convertidas à parte com ffmpeg (ver docs/R34-AUDIO-MODOS.md).

XEQUE:
  carta_baixar   cartas deslizando e batendo na mesa (cada jogada; 1 a 3 batidas = 1 a 3 cartas)
  sua_vez        aviso de "é a sua vez": dois toques de sino, curtos e claros
  xeque          alguém deu XEQUE: golpe grave + acorde metálico de alerta
  revelar        cartas viradas na revelação do XEQUE
  relogio        o relógio sendo acionado: corda + tique-taque acelerando
  seguro         o relógio NÃO disparou: estalo seco + respiro de alívio (nota que sobe)
  xeque_mate     o relógio explodiu: estrondo grave, estilhaços e eco
  eliminado      sino fúnebre grave
  vitoria / derrota   fanfarra curta / frase descendente
"""
import os
import wave
import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "xeque/audio")
rng = np.random.default_rng(33)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.2):
    x = np.arange(n) / SR
    e = np.minimum(1.0, x / max(a, 1e-4))
    return e * np.exp(-x / max(r, 1e-4))


def lowpass(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def highpass(x, fc):
    return x - lowpass(x, fc)


def tone(f, d, partials=((1, 1.0),), a=0.004, r=0.3):
    tt = t(d)
    s = sum(g * np.sin(2 * np.pi * f * k * tt) for k, g in partials)
    return s * env(len(tt), a, r)


def bell(f, d=1.2, r=0.45):
    # sino: parciais inarmônicas, como os sinos de mesa
    return tone(f, d, ((1, 1.0), (2.01, 0.55), (2.76, 0.35), (5.4, 0.18), (8.9, 0.08)), 0.002, r)


def mix(length, *parts):
    out = np.zeros(int(SR * length))
    for start, sig in parts:
        i = int(SR * start)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[:j - i]
    return out


def norm(x, peak=0.85):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(name, x, out_dir=None):
    out_dir = out_dir or OUT
    os.makedirs(out_dir, exist_ok=True)
    x = norm(x)
    fade = int(SR * 0.01)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(out_dir, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print(name + ".wav", round(len(x) / SR, 2), "s")


def card_tap(strength=1.0):
    # carta batendo na mesa de feltro: ruído curto filtrado + baque grave curto
    n = int(SR * 0.09)
    noise = highpass(lowpass(rng.normal(0, 1, n), 3800), 500) * env(n, 0.001, 0.018)
    thump = tone(150, 0.09, ((1, 1.0),), 0.001, 0.025) * 0.6
    return (noise + thump) * strength


def card_slide():
    n = int(SR * 0.14)
    x = highpass(lowpass(rng.normal(0, 1, n), 5200), 1200)
    e = np.sin(np.linspace(0, np.pi, n)) ** 2
    return x * e * 0.35


# cada jogada: deslize + 3 batidinhas (o jogo toca a versão de 1, 2 ou 3 cartas)
for k in (1, 2, 3):
    parts = [(0.0, card_slide())]
    for i in range(k):
        parts.append((0.10 + i * 0.075, card_tap(1.0 - i * 0.12)))
    save("carta_baixar_%d" % k, mix(0.32 + 0.075 * k, *parts))

# sua vez: dois toques de sino (mi5 → si5)
save("sua_vez", mix(1.1, (0.0, bell(659.25, 0.9, 0.35) * 0.8), (0.16, bell(987.77, 0.95, 0.4))))

# XEQUE: golpe grave + acorde de alerta (lá menor com sétima, metais)
hit = tone(70, 0.6, ((1, 1.0), (2, 0.4)), 0.002, 0.18)
hit += lowpass(rng.normal(0, 1, len(hit)), 900) * env(len(hit), 0.001, 0.05) * 0.8
brass = sum(tone(f, 0.75, ((1, 1.0), (2, 0.6), (3, 0.45), (4, 0.3), (5, 0.18)), 0.012, 0.32) for f in (220.0, 261.63, 329.63, 392.0))
save("xeque", mix(0.95, (0.0, hit), (0.03, brass * 0.55), (0.03, bell(1318.5, 0.6, 0.2) * 0.25)))

# revelar: três viradas de carta (deslize + estalo)
save("revelar", mix(0.6, (0.0, card_slide() * 0.8), (0.05, card_tap(0.7)), (0.18, card_slide() * 0.8), (0.23, card_tap(0.7)), (0.36, card_slide() * 0.8), (0.41, card_tap(0.7))))


def tick(f=2600, s=1.0):
    n = int(SR * 0.03)
    x = highpass(rng.normal(0, 1, n), 1800) * env(n, 0.0005, 0.006)
    return (x + tone(f, 0.03, ((1, 1.0),), 0.0005, 0.008) * 0.6) * s


# relógio acionado: corda (catraca) + tique-taque acelerando
parts = []
for i in range(7):
    parts.append((i * 0.045, tick(1500, 0.55)))
times = np.cumsum([0.24, 0.2, 0.17, 0.145, 0.125, 0.11, 0.1, 0.09])
for i, tm in enumerate(times):
    parts.append((0.35 + tm, tick(2600 if i % 2 == 0 else 2100, 0.9)))
save("relogio", mix(1.45, *parts))

# seguro: clique seco do mecanismo + nota que sobe (alívio)
relief = tone(392, 0.7, ((1, 1.0), (2, 0.3)), 0.02, 0.35) * 0.5 + tone(587.33, 0.7, ((1, 1.0), (2, 0.2)), 0.02, 0.35) * 0.4
save("seguro", mix(0.85, (0.0, tick(1200, 1.4)), (0.02, tone(110, 0.12, ((1, 1.0),), 0.001, 0.03) * 0.6), (0.12, relief)))

# XEQUE-MATE: o relógio explode — estrondo grave descendente, estilhaços metálicos e eco
d = 2.4
tt = t(d)
sweep = np.sin(2 * np.pi * np.cumsum(np.linspace(95, 28, len(tt))) / SR) * env(len(tt), 0.002, 0.55)
boom = lowpass(rng.normal(0, 1, len(tt)), 420) * env(len(tt), 0.001, 0.38) * 2.4
crack = highpass(rng.normal(0, 1, len(tt)), 2500) * env(len(tt), 0.0005, 0.06) * 0.9
shards = np.zeros(len(tt))
for i in range(22):
    st = rng.uniform(0.05, 0.9)
    f = rng.uniform(2200, 6500)
    sh = tone(f, 0.25, ((1, 1.0), (2.7, 0.4)), 0.0005, rng.uniform(0.03, 0.09)) * rng.uniform(0.08, 0.2)
    j = int(st * SR)
    shards[j:j + len(sh)] += sh[:len(shards) - j]
x = sweep * 1.2 + boom + crack + shards
echo = np.zeros_like(x)
for k, g in ((int(0.19 * SR), 0.35), (int(0.41 * SR), 0.18)):
    echo[k:] += lowpass(x[:-k], 1200) * g
save("xeque_mate", x + echo)

# eliminado: sino grave
save("eliminado", mix(1.8, (0.0, bell(146.83, 1.8, 0.8)), (0.0, bell(220.0, 1.6, 0.6) * 0.4)))

# vitória: fanfarra curta (dó–mi–sol–dó) / derrota: frase descendente
fan = lambda f, dd: tone(f, dd, ((1, 1.0), (2, 0.55), (3, 0.4), (4, 0.22)), 0.01, 0.35)
save("vitoria", mix(1.6, (0.0, fan(523.25, 0.3)), (0.14, fan(659.25, 0.3)), (0.28, fan(783.99, 0.3)), (0.44, fan(1046.5, 1.0) * 1.1), (0.44, bell(2093.0, 1.0, 0.4) * 0.2)))
save("derrota", mix(1.6, (0.0, fan(392.0, 0.45)), (0.28, fan(349.23, 0.45)), (0.56, fan(311.13, 0.45)), (0.84, fan(261.63, 0.8))))


# ======================================================================= MARCHA REAL
MOUT = os.path.join(ROOT, "marcha/audio")

def wood_step(f=900, s=1.0):
    # peão de madeira tocando a casa do tabuleiro
    n = int(SR * 0.07)
    x = lowpass(highpass(rng.normal(0, 1, n), 300), 2600) * env(n, 0.0008, 0.012)
    return (x + tone(f, 0.07, ((1, 1.0), (2.4, 0.3)), 0.0008, 0.018) * 0.7) * s

# carta jogada (1 carta) e descarte
save("carta", mix(0.4, (0.0, card_slide()), (0.1, card_tap(1.0))), MOUT)
save("descarte", mix(0.45, (0.0, card_slide() * 0.7), (0.08, card_slide() * 0.6), (0.18, card_tap(0.5))), MOUT)
# um passo do peão (tocado a cada casa durante a animação; a altura varia um pouco no jogo)
save("passo", wood_step(820, 1.0), MOUT)
# peão sai do pátio: toque de corneta curto (quinta ascendente)
horn = lambda f, dd: tone(f, dd, ((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)), 0.02, 0.25)
save("saida", mix(0.7, (0.0, horn(392.0, 0.18)), (0.13, horn(587.33, 0.5))), MOUT)
# captura: baque + peão voando de volta ao pátio (assobio descendente)
d = 0.6
tt = t(d)
whistle = np.sin(2 * np.pi * np.cumsum(np.linspace(1400, 380, len(tt))) / SR) * env(len(tt), 0.01, 0.2) * 0.35
thud = tone(95, d, ((1, 1.0), (2, 0.3)), 0.001, 0.09) + lowpass(rng.normal(0, 1, len(tt)), 700) * env(len(tt), 0.001, 0.04)
save("captura", mix(0.65, (0.0, thud), (0.04, whistle)), MOUT)
# troca de lugar (Valete): dois deslizes cruzados
sw = lambda f0, f1: np.sin(2 * np.pi * np.cumsum(np.linspace(f0, f1, int(SR * 0.22))) / SR) * np.sin(np.linspace(0, np.pi, int(SR * 0.22))) ** 2 * 0.4
save("troca", mix(0.45, (0.0, sw(500, 1100)), (0.12, sw(1100, 500))), MOUT)
# peão coroado: brilho de sinos subindo
save("coroa", mix(1.2, (0.0, bell(1046.5, 0.6, 0.25) * 0.6), (0.08, bell(1318.5, 0.6, 0.25) * 0.6), (0.16, bell(1568.0, 0.9, 0.35) * 0.7), (0.24, bell(2093.0, 0.9, 0.4) * 0.5)), MOUT)
# sua vez, vitória e derrota: os mesmos do XEQUE (mesma identidade sonora)
save("sua_vez", mix(1.1, (0.0, bell(659.25, 0.9, 0.35) * 0.8), (0.16, bell(987.77, 0.95, 0.4))), MOUT)
save("vitoria", mix(1.6, (0.0, fan(523.25, 0.3)), (0.14, fan(659.25, 0.3)), (0.28, fan(783.99, 0.3)), (0.44, fan(1046.5, 1.0) * 1.1), (0.44, bell(2093.0, 1.0, 0.4) * 0.2)), MOUT)
save("derrota", mix(1.6, (0.0, fan(392.0, 0.45)), (0.28, fan(349.23, 0.45)), (0.56, fan(311.13, 0.45)), (0.84, fan(261.63, 0.8))), MOUT)
