"""R35.1 · XEQUE: vozes masculinas "XEQUE!" e "XEQUE-MATE!" (sintetizadas aqui, sem gravação de terceiros).
Requer espeak-ng + mbrola-br3 (voz brasileira masculina, livre). Processamento: voz um pouco mais grave e
lenta (tom dramático), uma camada uma oitava abaixo bem baixa (corpo), reverberação de salão e normalização.
Saída: xeque/audio/voz_xeque.wav e xeque/audio/voz_xeque_mate.wav (44,1 kHz, mono, 16 bits)."""
import os, subprocess, tempfile, wave
import numpy as np
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "xeque/audio")
SR = 44100
rng = np.random.default_rng(35)

def tts(text, speed, pitch):
    f = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    subprocess.run(["espeak-ng", "-v", "mb-br3", "-s", str(speed), "-p", str(pitch), "-a", "180", "-w", f, text], check=True)
    w = wave.open(f); sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    os.unlink(f)
    nz = np.nonzero(np.abs(x) > 0.01)[0]
    return x[max(0, nz[0] - 200): nz[-1] + 400], sr

def resample(x, sr_in, factor):
    # factor < 1 → mais grave e mais lento (como fita mais lenta); saída em 44,1 kHz
    n_out = int(len(x) * SR / sr_in / factor)
    t = np.linspace(0, len(x) - 1, n_out)
    return np.interp(t, np.arange(len(x)), x)

def reverb(x, secs=1.1, mix=0.28):
    n = int(SR * secs)
    ir = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (SR * secs / 6.0))
    ir[:int(SR * 0.012)] = 0
    wet = np.convolve(x, ir)[: len(x) + n]
    wet = np.pad(wet, (0, len(x) + n - len(wet)))
    wet /= np.max(np.abs(wet)) + 1e-9
    out = np.zeros(len(x) + n); out[: len(x)] += x
    return out * (1 - mix) + wet * mix * np.max(np.abs(x))

def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    fade = int(SR * 0.05); x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print(name, round(len(x) / SR, 2), "s")

def voice(text, speed, pitch, factor):
    x, sr = tts(text, speed, pitch)
    main = resample(x, sr, factor)
    low = resample(x, sr, factor * 0.5)[: len(main)]         # uma oitava abaixo (só corpo)
    low = np.pad(low, (0, len(main) - len(low)))
    v = main + low * 0.18
    # leve saturação (voz "de locutor")
    v = np.tanh(v * 1.6) / np.tanh(1.6)
    return reverb(v)

save("voz_xeque", voice("Xêque!", 125, 28, 0.9))
save("voz_xeque_mate", voice("Xêque - mate!", 118, 24, 0.88))
