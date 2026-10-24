#!/usr/bin/env python3
"""R181 · coloca o RASTREAMENTO DA VISITA (web/telemetry/fraiha-track.js) no html/head_include dos presets Web.

Cada preset recebe o endereço do servidor DO SEU AMBIENTE (nunca produção numa build de teste):
  Web Alpha / Web Conteudo (staging) → https://fraiha-xadrez-staging.onrender.com/t
  Web Producao (production)          → https://fraiha-xadrez.onrender.com/t
Idempotente: o bloco anterior (entre /*fx-track:ini*/ e /*fx-track:fim*/) é trocado.
Uso: python3 tools/web_release/montar_rastreio_head.py [--terser CAMINHO]   (minifica com terser se houver)
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'web', 'telemetry', 'fraiha-track.js')
PRESETS = os.path.join(ROOT, 'export_presets.cfg')
URLS = {'staging': 'https://fraiha-xadrez-staging.onrender.com/t', 'production': 'https://fraiha-xadrez.onrender.com/t'}
MARK_A, MARK_B = '<script>/*fx-track:ini*/', '/*fx-track:fim*/</script>'


def minify(js, terser):
    if terser and os.path.exists(terser):
        r = subprocess.run([terser, '--compress', '--mangle'], input=js, capture_output=True, text=True, check=True)
        return r.stdout.strip()
    # sem terser: tira comentários de bloco no início e linhas em branco
    js = re.sub(r'/\*.*?\*/', '', js, flags=re.S)
    return '\n'.join(l.strip() for l in js.splitlines() if l.strip())


def cfg_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


def main():
    terser = None
    if '--terser' in sys.argv: terser = sys.argv[sys.argv.index('--terser') + 1]
    js = minify(open(SRC, encoding='utf-8').read(), terser)
    text = open(PRESETS, encoding='utf-8').read()
    sections = re.split(r'(?m)^(?=\[preset\.\d+\]$)', text)
    out, done = [], []
    feats = {}
    for sec in sections:
        m = re.match(r'\[preset\.(\d+)\]', sec)
        if m:
            name = re.search(r'(?m)^name="([^"]*)"', sec)
            f = re.search(r'(?m)^custom_features="([^"]*)"', sec)
            feats[m.group(1)] = (name.group(1) if name else '', f.group(1) if f else '')
        out.append(sec)
    text2 = ''.join(out)

    def fix(match_sec):
        sec = match_sec.group(0)
        num = re.match(r'\[preset\.(\d+)\.options\]', sec).group(1)
        name, f = feats.get(num, ('', ''))
        env = 'production' if 'production' in f else ('staging' if 'staging' in f else None)
        hm = re.search(r'(?m)^html/head_include="(.*)"$', sec)
        if not hm or env is None: return sec
        head = hm.group(1)
        head = re.sub(re.escape(cfg_escape(MARK_A)) + r'.*?' + re.escape(cfg_escape(MARK_B)), '', head)
        block = MARK_A + 'window.FRAIHA_TRACK_URL=' + '"' + URLS[env] + '";' + js + MARK_B
        head = cfg_escape(block) + head   # primeiro no <head>: registra mesmo se o resto falhar
        done.append(f'{name} → {URLS[env]}')
        return sec[:hm.start()] + 'html/head_include="' + head + '"' + sec[hm.end():]

    text3 = re.sub(r'(?ms)^\[preset\.\d+\.options\]$.*?(?=^\[preset\.|\Z)', fix, text2)
    open(PRESETS, 'w', encoding='utf-8').write(text3)
    for d in done: print('rastreio:', d)
    print(f'script: {len(js)} bytes')


if __name__ == '__main__':
    main()
