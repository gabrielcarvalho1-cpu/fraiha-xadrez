"""R36 · XEQUE: efeitos sonoros mais impactantes (sintetizados aqui, sem amostras de terceiros).
Não altera os .wav anteriores (tools/mode_sfx.py); gera arquivos novos em xeque/audio/:
  xeque_impacto     alguém pediu XEQUE: sucção reversa + estrondo grave + golpe metálico + cauda de salão
  virar_carta       as cartas da última jogada viram (sopro curto)
  relogio_tensao    relógio acionado: tique-taque acelerando + coração batendo + corda subindo (≈2,4 s)
  seguro_alivio     o relógio NÃO estourou: sino brilhante subindo + respiro
  xeque_mate_boom   o relógio estourou: clarão sub-grave, explosão de ruído, estilhaços e eco longo (≈3,5 s)
  derrota_final     fim de partida (derrota): metais descendentes + tambor grave
  baralho_intro     apresentação do baralho antes da 1ª rodada (cartas abrindo em leque + acorde)
44,1 kHz, mono, 16 bits."""
import os
import wave
import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "xeque/audio")
rng = np.random.default_rng(3636)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.2):
    x = np.arange(n) / SR
    return np.minimum(1.0, x / max(a, 1e-4)) * np.exp(-x / max(r, 1e-4))


def lowpass(x, fc):
    # filtro de 1 polo (vetorizado por blocos com lfilter caseiro)
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def highpass(x, fc):
    return x - lowpass(x, fc)


def tone(f, d, partials=((1, 1.0),), a=0.004, r=0.3):
    tt = t(d)
    return sum(g * np.sin(2 * np.pi * f * k * tt) for k, g in partials) * env(len(tt), a, r)


def sweep(f0, f1, d, a=0.002, r=1.0):
    n = int(SR * d)
    ph = 2 * np.pi * np.cumsum(np.geomspace(f0, f1, n)) / SR
    return np.sin(ph) * env(n, a, r)


def bell(f, d=1.2, r=0.45):
    return tone(f, d, ((1, 1.0), (2.01, 0.55), (2.76, 0.35), (5.4, 0.18), (8.9, 0.08)), 0.002, r)


def noise(d, lo=0, hi=None):
    x = rng.normal(0, 1, int(SR * d))
    if hi: x = lowpass(x, hi)
    if lo: x = highpass(x, lo)
    return x


def mix(length, *parts):
    out = np.zeros(int(SR * length))
    for start, sig in parts:
        i = int(SR * start)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[:j - i]
    return out


def reverb(x, secs=1.4, mix_=0.3):
    n = int(SR * secs)
    ir = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (SR * secs / 5.0))
    ir[: int(SR * 0.015)] = 0
    wet = np.convolve(x, ir)[: len(x) + n]
    wet = np.pad(wet, (0, len(x) + n - len(wet)))
    wet /= np.max(np.abs(wet)) + 1e-9
    dry = np.pad(x, (0, n))
    return dry * (1 - mix_) + wet * mix_ * np.max(np.abs(x))


def save(name, x, peak=0.92):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * 0.03)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print(name + ".wav", round(len(x) / SR, 2), "s")


# ---------------------------------------------------------------- XEQUE!
rev = noise(0.45, 200, 6000) * np.linspace(0, 1, int(SR * 0.45)) ** 3 * 0.5          # sucção reversa
boom = tone(48, 1.4, ((1, 1.0), (2, 0.5), (3, 0.2)), 0.002, 0.35) * 1.4
hit = noise(0.25, 300, 7000) * env(int(SR * 0.25), 0.0005, 0.04) * 0.9
metal = tone(311, 1.2, ((1, 1.0), (2.41, 0.6), (3.9, 0.35), (6.1, 0.2)), 0.001, 0.35) * 0.45
save("xeque_impacto", reverb(mix(1.9, (0.0, rev), (0.45, boom), (0.45, hit), (0.46, metal)), 1.6, 0.32))

# cartas virando
n = int(SR * 0.28)
save("virar_carta", mix(0.4, (0.0, highpass(lowpass(rng.normal(0, 1, n), 7000), 900) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.6),
                        (0.2, tone(180, 0.1, ((1, 1.0),), 0.001, 0.03) * 0.5)))

# relógio acionado: tique-taque acelerando + coração + corda subindo
d = 2.4
ticks = np.zeros(int(SR * d))
tt_ = 0.0
gap = 0.32
k = 0
while tt_ < d - 0.05:
    f = 2900 if k % 2 == 0 else 2300
    tk = tone(f, 0.04, ((1, 1.0), (2.7, 0.3)), 0.0005, 0.008) * (0.5 + 0.5 * tt_ / d)
    i = int(tt_ * SR); ticks[i:i + len(tk)] += tk[: len(ticks) - i]
    tt_ += gap; gap = max(0.07, gap * 0.86); k += 1
heart = np.zeros(int(SR * d))
for hb in np.arange(0.1, d, 0.62):
    for off, amp in ((0.0, 1.0), (0.17, 0.7)):
        b = tone(55, 0.22, ((1, 1.0), (2, 0.3)), 0.004, 0.06) * amp
        i = int((hb + off) * SR); heart[i:i + len(b)] += b[: len(heart) - i]
riser = sweep(120, 900, d, 0.4, 9) * np.linspace(0.05, 0.4, int(SR * d))
save("relogio_tensao", ticks * 0.8 + heart * 1.1 + riser)

# seguro: sino subindo + respiro
breath = noise(0.8, 300, 2500) * env(int(SR * 0.8), 0.15, 0.25) * 0.25
save("seguro_alivio", reverb(mix(1.6, (0.0, bell(784, 1.0, 0.35) * 0.5), (0.1, bell(1046.5, 1.0, 0.4) * 0.55), (0.2, bell(1568, 1.2, 0.5) * 0.6), (0.3, breath)), 1.2, 0.25))

# XEQUE-MATE: explosão
d = 3.6
sub = sweep(90, 28, 2.0, 0.001, 0.7) * 1.6
blast = noise(2.5, 0, 2400) * env(int(SR * 2.5), 0.002, 0.45) * 1.3
crack = noise(0.12, 1500, 0) * env(int(SR * 0.12), 0.0003, 0.02) * 1.2
shards = np.zeros(int(SR * d))
for _ in range(70):
    st = rng.uniform(0.05, 1.6)
    sh = tone(rng.uniform(2500, 7000), 0.08, ((1, 1.0), (1.6, 0.4)), 0.0005, rng.uniform(0.01, 0.04)) * rng.uniform(0.05, 0.25)
    i = int(st * SR); shards[i:i + len(sh)] += sh[: len(shards) - i]
rumble = noise(d, 0, 140) * np.linspace(1, 0, int(SR * d)) ** 2 * 0.9
x = mix(d, (0.0, sub), (0.0, blast), (0.0, crack), (0.0, shards), (0.0, rumble))
save("xeque_mate_boom", reverb(x, 2.2, 0.35))

# derrota: metais descendentes + tambor
brass = lambda f, dd: tone(f, dd, ((1, 1.0), (2, 0.6), (3, 0.45), (4, 0.3), (5, 0.15)), 0.03, 0.5)
drum = lambda: tone(60, 0.7, ((1, 1.0), (1.5, 0.3)), 0.001, 0.18) + noise(0.7, 0, 500) * env(int(SR * 0.7), 0.001, 0.06) * 0.6
save("derrota_final", reverb(mix(3.4, (0.0, drum()), (0.0, brass(392, 0.7)), (0.55, drum() * 0.8), (0.55, brass(349.2, 0.7)),
                                 (1.1, drum() * 0.9), (1.1, brass(311.1, 0.7)), (1.65, drum() * 1.2), (1.65, brass(261.6, 1.6) * 1.1),
                                 (1.65, brass(196, 1.6) * 0.6)), 1.6, 0.3))

# apresentação do baralho: cartas abrindo em leque + acorde
fan = np.zeros(int(SR * 2.2))
for i in range(8):
    nn = int(SR * 0.12)
    s = highpass(lowpass(rng.normal(0, 1, nn), 6000), 1500) * np.sin(np.linspace(0, np.pi, nn)) ** 2 * 0.35
    j = int((0.05 + i * 0.09) * SR); fan[j:j + nn] += s
chord = sum(tone(f, 1.4, ((1, 1.0), (2, 0.4), (3, 0.2)), 0.02, 0.6) for f in (261.6, 329.6, 392.0, 523.3)) * 0.35
save("baralho_intro", reverb(mix(2.4, (0.0, fan), (0.8, chord), (0.8, bell(1046.5, 1.2, 0.5) * 0.3)), 1.2, 0.25))
