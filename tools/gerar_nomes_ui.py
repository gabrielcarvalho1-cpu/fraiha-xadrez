#!/usr/bin/env python3
"""R181 · LISTA DE NOMES CONHECIDOS (telas e botões) para o rastreamento sem login (rota /t do servidor).

Só entra no painel um nome de tela/botão que EXISTE no código do jogo (texto fixo num .gd ou nos JSON do jogo).
Assim nada digitado pela pessoa (e-mail, senha, chat, apelido) pode passar: não está em nenhum arquivo do jogo.
Textos com %s/%d (ex.: "%s TE DESAFIOU! JOGAR AGORA") viram padrão: o %s só aceita letras/números/espaço, até 30.

Uso: python3 tools/gerar_nomes_ui.py   → escreve online_v021/admin/ui_names.json (commitado junto com o jogo).
Rodar de novo sempre que mudar texto de botão/tela (o teste tests/server/rastreio_visitante_r181_test.cjs confere
que a lista está em dia com o código).
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'online_v021', 'admin', 'ui_names.json')
SKIP_DIRS = {'tests', '.git', '.godot', 'node_modules', 'online_v021', 'admin', 'tools', 'docs', 'addons', 'web', 'supabase'}
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
JSON_FILES = ['bot/bot_ladder.json']


def norm(s: str) -> str:
    s = s.replace('\\n', ' ').replace('\\"', '"').replace('\\t', ' ')
    s = re.sub(r'\s+', ' ', s).strip().upper()
    return s


def keep(s: str) -> bool:
    if len(s) < 2 or len(s) > 60: return False
    if not re.search(r'[A-ZÀ-Ý]', s): return False
    if re.search(r'(RES://|USER://|HTTPS?://|\.GD$|\.PNG$|\.JSON$|\.TSCN$|[{}<>\[\]=@#$&|\\])', s): return False
    return True


def main():
    names, patterns = set(), set()
    for d, dirs, files in os.walk(ROOT):
        rel = os.path.relpath(d, ROOT)
        if rel.split(os.sep)[0] in SKIP_DIRS: dirs[:] = []; continue
        dirs[:] = [x for x in dirs if not x.startswith('.')]
        for f in files:
            if not f.endswith('.gd'): continue
            with open(os.path.join(d, f), encoding='utf-8', errors='ignore') as fh:
                for line in fh:
                    code = line.split('#', 1)[0] if '"' not in line.split('#', 1)[0] else line
                    for m in LIT.finditer(code):
                        n = norm(m.group(1))
                        if not keep(n.replace('%S', 'X').replace('%D', '0')): continue
                        if re.search(r'%[SD0-9.]', n):
                            fixed = re.sub(r'%[-0-9.]*[SDF%]', '', n)
                            if len(re.sub(r'[^A-ZÀ-Ý]', '', fixed)) >= 5: patterns.add(n)   # padrão precisa de texto fixo
                        else: names.add(n)
    for jf in JSON_FILES:
        p = os.path.join(ROOT, jf)
        if not os.path.exists(p): continue
        def walk(v):
            if isinstance(v, str):
                n = norm(v)
                if keep(n): names.add(n)
            elif isinstance(v, list):
                for x in v: walk(x)
            elif isinstance(v, dict):
                for x in v.values(): walk(x)
        walk(json.load(open(p, encoding='utf-8')))
    out = {'gerado_por': 'tools/gerar_nomes_ui.py', 'names': sorted(names), 'patterns': sorted(patterns)}
    with open(OUT, 'w', encoding='utf-8') as fh: json.dump(out, fh, ensure_ascii=False, indent=0)
    print(f'{len(names)} nomes, {len(patterns)} padrões → {os.path.relpath(OUT, ROOT)} ({os.path.getsize(OUT) // 1024} KB)')


if __name__ == '__main__':
    sys.exit(main())
