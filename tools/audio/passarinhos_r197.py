# R197 · PASSARINHOS da Home (gerado, sem gravação de terceiros): cantos curtos e espaçados de 3 "espécies",
# com eco leve de floresta e um fundo de ar quase inaudível. Laço perfeito de 24 s. Saída: audio_v025/passarinhos.ogg
import numpy as np, subprocess, sys
from scipy.signal import butter, sosfiltfilt, fftconvolve
SR = 44100; L = 24.0; N = int(SR * L)
rng = np.random.default_rng(1971)
def env(n, a=0.08, r=0.6):
    t = np.linspace(0, 1, n); return np.minimum(1, t / a) * np.exp(-t / r * 3) * (1 - t) ** 0.5
def tone(f0, f1, dur, vib=0.0, vf=30.0, curve=1.0):
    n = int(SR * dur); t = np.arange(n) / SR; u = (t / dur) ** curve
    f = f0 + (f1 - f0) * u + vib * np.sin(2 * np.pi * vf * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)) * env(n)
def sp_a():   # trinado agudo descendo (tipo bem-te-vi pequeno)
    parts = []
    for k in range(rng.integers(3, 6)):
        f = rng.uniform(4200, 5200) - k * 120
        parts += [tone(f, f - 1400, rng.uniform(0.05, 0.07), curve=0.7), np.zeros(int(SR * rng.uniform(0.03, 0.05)))]
    return np.concatenate(parts)
def sp_b():   # dois assobios: sobe e desce
    f = rng.uniform(2600, 3200)
    return np.concatenate([tone(f, f + 700, 0.16, vib=60, vf=24), np.zeros(int(SR * 0.08)), tone(f + 500, f - 300, 0.22, vib=40, vf=18)])
def sp_c():   # piu-piu curtinho
    f = rng.uniform(5200, 6300); out = []
    for _ in range(rng.integers(2, 4)):
        out += [tone(f, f + rng.uniform(-300, 600), 0.035, curve=0.5), np.zeros(int(SR * rng.uniform(0.06, 0.1)))]
    return np.concatenate(out)
def track(pan_bias):
    y = np.zeros(N + SR * 2)
    t = rng.uniform(0.5, 2.0)
    while t < L - 0.5:
        s = [sp_a, sp_b, sp_c][rng.choice(3, p=[0.35, 0.3, 0.35])]() * rng.uniform(0.25, 0.6)
        i = int(t * SR); y[i:i + len(s)] += s
        t += rng.uniform(1.6, 3.8)
    return y
mono = track(0)
# eco de floresta (resposta curta e difusa)
ir = np.zeros(int(SR * 0.6)); idx = rng.integers(200, len(ir), 60); ir[idx] = rng.uniform(-1, 1, 60) * np.exp(-idx / SR * 9); ir[0] = 1
wet = fftconvolve(mono, ir)[:len(mono)]
air = sosfiltfilt(butter(2, [300 / (SR / 2), 2500 / (SR / 2)], btype="band", output="sos"), rng.standard_normal(len(mono))) * 0.004
def ch(delay):
    d = np.concatenate([np.zeros(delay), wet])[:len(wet)]
    return d + air
l, r = ch(0), ch(int(SR * 0.0007))
# laço: o que passa de L volta no começo
for x in (l, r): x[:len(x) - N] += x[N:]
l, r = l[:N], r[:N]
m = 0.8 / max(np.abs(l).max(), np.abs(r).max())
pcm = (np.stack([l, r], 1) * m * 32767).astype("<i2")
out = sys.argv[1] if len(sys.argv) > 1 else "audio_v025/passarinhos.ogg"
p = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", "libvorbis", "-q:a", "2", out], input=pcm.tobytes())
print("ok", p.returncode)
