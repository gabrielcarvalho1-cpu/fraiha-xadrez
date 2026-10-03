"""R37 · MARCHA REAL: som da chegada ao Salão (peão vira DAMA) — fanfarra real, sintetizada aqui.
Rufar de tímpano → metais subindo em arpejo (Dó–Mi–Sol–Dó) → acorde cheio com coro e sinos, prato
abrindo e cauda de salão. Gera marcha/audio/promocao_dama.wav (44,1 kHz, mono, 16 bits)."""
import os
import wave
import numpy as np
from scipy.signal import lfilter

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "marcha/audio/promocao_dama.wav")
rng = np.random.default_rng(37)


def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=0.3):
    x = np.arange(n) / SR
    return np.minimum(1.0, x / max(a, 1e-4)) * np.exp(-x / max(r, 1e-4))
def lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    return lfilter([1 - a], [1, -a], x)
def hp(x, fc): return x - lp(x, fc)
def noise(d): return rng.normal(0, 1, int(SR * d))


def brass(f, d, a=0.04, r=0.9, vib=True):
    tt = t(d)
    fm = f * (1 + (0.004 * np.sin(2 * np.pi * 5.5 * tt) * np.clip(tt / 0.3, 0, 1) if vib else 0))
    ph = 2 * np.pi * np.cumsum(fm) / SR
    x = sum(g * np.sin(k * ph) for k, g in [(1, 1.0), (2, 0.7), (3, 0.55), (4, 0.4), (5, 0.28), (6, 0.18), (7, 0.1)])
    bright = np.clip(tt / 0.08, 0, 1)
    x = lp(x, 1800 + 2600 * 1) * 0.7 + x * 0.3 * bright
    e = np.minimum(1, tt / a) * np.where(tt < d - 0.25, 1.0, np.clip((d - tt) / 0.25, 0, 1)) * (0.85 + 0.15 * np.exp(-tt / r))
    return x * e


def choir(f, d):
    tt = t(d)
    x = np.zeros_like(tt)
    for det in (-0.006, 0.0, 0.005):
        ph = 2 * np.pi * f * (1 + det) * tt + 0.3 * np.sin(2 * np.pi * 4.8 * tt)
        x += sum(g * np.sin(k * ph) for k, g in [(1, 1.0), (2, 0.45), (3, 0.25), (4, 0.12)])
    x = lp(x, 1400)
    e = np.clip(tt / 0.35, 0, 1) * np.clip((d - tt) / 0.6, 0, 1)
    return x * e


def bell(f, d=1.6, r=0.6):
    tt = t(d)
    return sum(g * np.sin(2 * np.pi * f * k * tt) for k, g in [(1, 1.0), (2.01, 0.5), (2.76, 0.35), (5.4, 0.15)]) * env(len(tt), 0.002, r)


def timp(f, d=0.9, r=0.35):
    tt = t(d)
    x = np.sin(2 * np.pi * f * tt * (1 + 0.04 * np.exp(-tt / 0.05))) + 0.4 * np.sin(2 * np.pi * f * 1.5 * tt)
    return x * env(len(tt), 0.002, r) + lp(noise(d), 600) * env(len(tt), 0.001, 0.04) * 0.5


def mix(length, *parts):
    out = np.zeros(int(SR * length))
    for start, sig in parts:
        i = int(SR * start)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[:j - i]
    return out


def reverb(x, secs=1.8, wet=0.3):
    n = int(SR * secs)
    ir = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (SR * secs / 5.0))
    ir[: int(SR * 0.02)] = 0
    w = np.convolve(x, ir)[: len(x)]
    w = w / (np.max(np.abs(w)) + 1e-9) * np.max(np.abs(x))
    return x * (1 - wet) + w * wet


D = 3.2
parts = []
# rufar de tímpano (0 → 0,45 s), crescendo
for k, st in enumerate(np.arange(0.0, 0.45, 0.045)):
    parts.append((st, timp(98, 0.4, 0.12) * (0.35 + 0.65 * k / 10)))
parts.append((0.48, timp(65.4, 1.2, 0.5) * 1.5))                      # golpe grave na chegada
# arpejo de metais: Dó4 Mi4 Sol4 → Dó5 longo
for st, f, d in [(0.48, 261.6, 0.22), (0.62, 329.6, 0.22), (0.76, 392.0, 0.22)]:
    parts.append((st, brass(f, d, 0.015) * 0.8))
for f, g in [(523.3, 1.0), (392.0, 0.7), (329.6, 0.6), (261.6, 0.6), (130.8, 0.5)]:
    parts.append((0.92, brass(f, 1.9, 0.03) * g * 0.75))
# coro e sinos sobre o acorde
for f in (261.6, 329.6, 392.0, 523.3):
    parts.append((0.92, choir(f, 2.2) * 0.35))
for st, f in [(0.92, 1046.5), (1.05, 1318.5), (1.18, 1568.0), (1.31, 2093.0)]:
    parts.append((st, bell(f, 1.6, 0.55) * 0.22))
# prato abrindo (swell) + choque no acorde
cym = hp(noise(2.2), 4000) * env(int(SR * 2.2), 0.002, 0.7)
swell = hp(noise(0.5), 5000) * np.linspace(0, 1, int(SR * 0.5)) ** 2
parts += [(0.42, swell * 0.25), (0.92, cym * 0.35)]
x = reverb(mix(D, *parts), 2.0, 0.28)
x = x / (np.max(np.abs(x)) + 1e-9) * 0.95
fade = int(SR * 0.25)
x[-fade:] *= np.linspace(1, 0, fade)
with wave.open(OUT, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
print("ok", OUT, round(len(x) / SR, 2), "s")
