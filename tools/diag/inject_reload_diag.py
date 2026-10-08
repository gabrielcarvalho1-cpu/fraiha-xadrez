"""FRAIHA · injeta o diagnóstico TEMPORÁRIO de reload (reload_diag.js) numa build Web JÁ EXPORTADA.
Uso: python tools/diag/inject_reload_diag.py <pasta_da_build_web>
Só para uma build de teste. Não rode sobre a build que vai para o Cloudflare.
Na build injetada, o diário só liga com ?diag=1 na URL (e desliga com ?diag=0)."""
import os, shutil, sys

out = sys.argv[1]
html = os.path.join(out, "index.html")
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "reload_diag.js")
shutil.copy(src, os.path.join(out, "reload_diag.js"))
s = open(html, encoding="utf-8").read()
tag = '<script src="reload_diag.js"></script>'
if tag not in s:
    s = s.replace("<head>", "<head>\n" + tag, 1)
    open(html, "w", encoding="utf-8").write(s)
print("diag injetado em", html)
