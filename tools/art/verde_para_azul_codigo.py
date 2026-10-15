#!/usr/bin/env python3
"""R113 · troca os VERDES-ESCUROS de painéis/botões desenhados em código (Color("hex") e Color(r, g, b[, a]))
pelo azul do jogo — mesma regra de tools/art/verde_para_azul.py. Verdes claros com significado (online,
vitória, PIX, cores de reino/liga, classificação de lances) ficam. Uso: python3 ... [--dry] arquivo.gd ..."""
import re, sys, colorsys

H_TARGET = 220.0 / 360.0
V_LIFT = 0.45

def conv(r, g, b):
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if not (100 / 360 <= h <= 185 / 360) or s < 0.15 or l > 0.32: return None
    hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
    vv = min(1.0, vv * (1.0 + V_LIFT * (1.0 - vv)))
    return colorsys.hsv_to_rgb(H_TARGET, ss, vv)

HEX = re.compile(r'Color\("(#?)([0-9a-fA-F]{6})([0-9a-fA-F]{2})?"')
NUM = re.compile(r'Color\(\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)(?=\s*[,)])')

def fix(text):
    n = 0
    def h(m):
        nonlocal n
        c = m.group(2); r, g, b = [int(c[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        out = conv(r, g, b)
        if out is None: return m.group(0)
        n += 1
        return 'Color("%s%02x%02x%02x%s"' % (m.group(1), *[round(x * 255) for x in out], m.group(3) or '')
    def f(m):
        nonlocal n
        vals = [float(x) for x in m.groups()]
        if max(vals) > 1.0: return m.group(0)
        out = conv(*vals)
        if out is None: return m.group(0)
        n += 1
        return 'Color(%.3f, %.3f, %.3f' % out
    text = HEX.sub(h, text)
    text = NUM.sub(f, text)
    return text, n

if __name__ == '__main__':
    dry = '--dry' in sys.argv
    for p in [a for a in sys.argv[1:] if not a.startswith('--')]:
        s = open(p, encoding='utf-8').read()
        t, n = fix(s)
        if n:
            print('%3d  %s' % (n, p))
            if not dry: open(p, 'w', encoding='utf-8', newline='').write(t)
