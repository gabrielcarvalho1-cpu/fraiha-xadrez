"""R77 · Build Web mais leve (iPhone recarregava por falta de memória).

As artes grandes (PNG > LIMITE) passam a ser importadas como WebP COM PERDA, qualidade alta (0.9): o pacote .pck
(que o navegador guarda inteiro na memória) encolhe muito; o desenho na tela é praticamente o mesmo.
Ícones, cartas e peças pequenas continuam sem perda.

Os .import não vão para o Git (são gerados pelo Godot), então este script é o lugar versionado dessa regra:
rode-o ANTES do --import/--export da build Web.
Uso: python3 tools/web_release/texturas_leves.py [--desfazer]
"""
import os, re, sys

LIMITE = 250 * 1024
QUAL = "0.9"
RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FORA = ("tools/", "tests/", "docs/", "web/", ".godot/", ".git/")


def main():
    desfazer = "--desfazer" in sys.argv
    n = 0
    for root, _, fs in os.walk(RAIZ):
        rel_root = os.path.relpath(root, RAIZ).replace(os.sep, "/") + "/"
        if rel_root.startswith(FORA): continue
        for f in fs:
            if not f.endswith(".png.import"): continue
            imp = os.path.join(root, f)
            png = imp[:-len(".import")]
            if not os.path.exists(png) or os.path.getsize(png) < LIMITE: continue
            s = open(imp, encoding="utf-8").read()
            novo = re.sub(r"compress/mode=\d", "compress/mode=%d" % (0 if desfazer else 1), s)
            novo = re.sub(r"compress/lossy_quality=[\d.]+", "compress/lossy_quality=%s" % ("0.7" if desfazer else QUAL), novo)
            if novo != s:
                open(imp, "w", encoding="utf-8").write(novo)
                n += 1
    print("%s: %d texturas" % ("lossless" if desfazer else "WebP com perda q=" + QUAL, n))


if __name__ == "__main__":
    main()
