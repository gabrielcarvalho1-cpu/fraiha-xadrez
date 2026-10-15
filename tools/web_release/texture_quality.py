#!/usr/bin/env python3
"""R106 · Qualidade das imagens do pacote Web (aprovada pelo dono em 15/10/2026: WebP 0,75).

As configurações de importação (*.png.import) são geradas pelo Godot e NÃO vão para o Git (regra do projeto).
Por isso a qualidade é aplicada por este passo, ANTES do export:

    python3 tools/web_release/texture_quality.py            # aplica 0,75 nas imagens com compressão com perda
    python3 tools/web_release/texture_quality.py --check    # só confere (sai com erro se alguma estiver diferente)

Só mexe em imagens que já usam compressão com perda (compress/mode=1). As sem perda (mode=0: pixel art fina,
ícones, molduras recortadas) não mudam. Pastas fora do pacote (tools, tests, docs, web) são ignoradas.
O Godot reimporta sozinho no export quando o .import muda.
"""
import pathlib
import re
import sys

QUALITY = "0.75"
SKIP = ("tools/", "tests/", "docs/", "web/", ".godot/", "node_modules/")


def targets(root: pathlib.Path):
    for p in sorted(root.rglob("*.png.import")):
        rel = p.relative_to(root).as_posix()
        if rel.startswith(SKIP):
            continue
        text = p.read_text(encoding="utf-8")
        if re.search(r"^compress/mode=1$", text, re.M):
            yield p, text


def main() -> int:
    root = pathlib.Path(__file__).resolve().parents[2]
    check = "--check" in sys.argv
    changed = wrong = total = 0
    for p, text in targets(root):
        total += 1
        new = re.sub(r"^compress/lossy_quality=[0-9.]+$", "compress/lossy_quality=" + QUALITY, text, flags=re.M)
        if "compress/lossy_quality=" not in new:
            new = new.replace("compress/mode=1\n", "compress/mode=1\ncompress/lossy_quality=" + QUALITY + "\n", 1)
        if new != text:
            if check:
                wrong += 1
                print("DIFERENTE", p.relative_to(root))
            else:
                p.write_text(new, encoding="utf-8")
                changed += 1
    if check:
        print(f"texture_quality: {total} imagens com perda, {wrong} fora de {QUALITY}")
        return 1 if wrong else 0
    print(f"texture_quality: {total} imagens com perda, {changed} ajustadas para {QUALITY}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
