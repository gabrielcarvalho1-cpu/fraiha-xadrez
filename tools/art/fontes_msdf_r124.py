#!/usr/bin/env python3
"""R124 · fontes prontas para MSDF (letras nítidas e espaçamento certo em qualquer escala da tela).
O MSDF do Godot desenha errado alguns glifos COMPOSTOS (ex.: "Ã" do Cinzel virava um bloco). Aqui cada glifo
composto vira contornos simples (decomposto), sem mudar o desenho. Grava por cima (o original fica no git).
Uso: python3 tools/art/fontes_msdf_r124.py fonte.woff ..."""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

def decompose(path):
    f = TTFont(path)
    glyf = f["glyf"]
    gs = f.getGlyphSet()
    n = 0
    for name in list(glyf.keys()):
        g = glyf[name]
        if not g.isComposite(): continue
        pen = TTGlyphPen(gs)
        gs[name].draw(pen)
        glyf[name] = pen.glyph()
        n += 1
    # contornos soltos (fora de qualquer outro) desenhados no sentido de "furo" (ex.: o til do Cinzel): inverte
    fixed = 0
    for name in list(glyf.keys()):
        g = glyf[name]
        if g.isComposite() or g.numberOfContours <= 0: continue
        coords, ends, flags = g.getCoordinates(glyf)
        cs, s0 = [], 0
        for e in ends:
            cs.append(list(range(s0, e + 1))); s0 = e + 1
        def area(ix):
            a = 0
            for i in range(len(ix)):
                x1, y1 = coords[ix[i]]; x2, y2 = coords[ix[(i + 1) % len(ix)]]
                a += x1 * y2 - x2 * y1
            return a / 2
        def bbox(ix):
            xs = [coords[i][0] for i in ix]; ys = [coords[i][1] for i in ix]
            return min(xs), min(ys), max(xs), max(ys)
        boxes = [bbox(c) for c in cs]
        changed = False
        for k, c in enumerate(cs):
            b = boxes[k]
            inside = any(j != k and boxes[j][0] <= b[0] and boxes[j][1] <= b[1] and boxes[j][2] >= b[2] and boxes[j][3] >= b[3] for j in range(len(cs)))
            if not inside and area(c) > 0:
                rev = [c[0]] + c[1:][::-1]
                pts = [coords[i] for i in rev]; fl = [flags[i] for i in rev]
                for t, i in enumerate(c):
                    coords[i] = pts[t]; flags[i] = fl[t]
                changed = True
        if changed:
            g.coordinates = coords; g.flags = flags
            fixed += 1
    print("  contornos invertidos em", fixed, "glifos")
    f.flavor = "woff2" if path.endswith(".woff2") else "woff"
    f.save(path)
    print(path, n, "glifos decompostos")

for p in sys.argv[1:]: decompose(p)
