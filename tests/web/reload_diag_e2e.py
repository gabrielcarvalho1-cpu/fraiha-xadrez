"""R52f · Diagnóstico temporário de reload (tools/diag/reload_diag.js) no Chromium real.
Serve uma página mínima com o script de verdade e confere: inativo sem ?diag=1; ativação de 24 h; ?diag=0;
schema inválido no localStorage descartado sem erro; WebGL perdido registrado uma vez; texto de erro redigido;
reload limpo = SAÍDA REGISTRADA; queda sem pagehide = DESCONHECIDO (sem afirmar falta de memória).
Rodar: python3 tests/web/reload_diag_e2e.py   (CHROME=<binário> opcional)   · sai com 1 se algum FAIL."""
import asyncio, functools, http.server, json, os, socketserver, sys, tempfile, threading
from playwright.async_api import async_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
JS = open(os.path.join(HERE, "../../tools/diag/reload_diag.js"), encoding="utf-8").read()
PAGE = """<!doctype html><html><head><meta charset="utf-8"><script src="reload_diag.js"></script></head>
<body><canvas id="canvas" width="64" height="64"></canvas>
<script>window.ctx = document.getElementById('canvas').getContext('webgl2');</script></body></html>"""
root = tempfile.mkdtemp(prefix="fraiha_diag_")
open(os.path.join(root, "index.html"), "w", encoding="utf-8").write(PAGE)
open(os.path.join(root, "reload_diag.js"), "w", encoding="utf-8").write(JS)
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
srv = socketserver.TCPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=root))
threading.Thread(target=srv.serve_forever, daemon=True).start()
B = "http://127.0.0.1:%d/index.html" % srv.server_address[1]
CHROME = os.environ.get("CHROME") or None
K = "fraiha_diag_v1"
res = []
def ck(ok, label): res.append(ok); print("PASS" if ok else "FAIL", label)
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path=CHROME, args=["--use-angle=swiftshader","--enable-unsafe-swiftshader","--no-proxy-server"])
        ctx = await b.new_context()
        pg = await ctx.new_page()
        async def st(): return await pg.evaluate(f"[localStorage.getItem('{K}'), localStorage.getItem('{K}_on'), !!document.querySelector('pre'), [...document.querySelectorAll('div')].some(d=>d.textContent.startsWith('DIAG'))]")
        await pg.goto(B); await asyncio.sleep(0.5)
        s = await st(); ck(s[0] is None and s[1] is None and not s[2] and not s[3], "sem ?diag=1: nada gravado, sem selo, sem caixa")
        await pg.goto(B + "?diag=1"); await asyncio.sleep(0.5)
        s = await st(); ck(s[0] is not None and s[1] is not None and s[3] and not s[2], "?diag=1: liga, grava e mostra o selo")
        # erro com dados sensíveis + perda de contexto WebGL
        await pg.evaluate("setTimeout(()=>{throw new Error('falhou https://x.supabase.co/auth?access_token=abc123 usuario fulano@mail.com eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.abcdefghij')},0)")
        await pg.evaluate("ctx.getExtension('WEBGL_lose_context').loseContext()")
        await asyncio.sleep(0.8)
        cur = json.loads((await st())[0])["cur"]
        errs = [e for e in cur["ev"] if e["k"] == "error"]
        lost = [e for e in cur["ev"] if e["k"] == "webgl_lost"]
        ck(len(lost) == 1, "perda de WebGL registrada UMA vez (achou %d)" % len(lost))
        msg = errs[0]["msg"] if errs else ""
        ck(errs and "access_token" not in msg and "abc123" not in msg and "fulano@mail.com" not in msg and "eyJ" not in msg and "<email>" in msg, "erro redigido: " + msg)
        # reload limpo SEM a query: continua ligado e classifica como saída registrada
        await pg.goto(B); await asyncio.sleep(0.6)
        txt = await pg.evaluate("document.querySelector('pre') ? document.querySelector('pre').textContent : ''")
        ck("SAÍDA REGISTRADA" in txt and (await st())[3], "sem a query (dentro de 24 h) continua ligado; reload limpo = SAÍDA REGISTRADA")
        # aba que cai (crash) -> DESCONHECIDO, nunca 'OOM'
        cdp = await ctx.new_cdp_session(pg)
        try: await asyncio.wait_for(cdp.send("Page.crash"), 3)
        except Exception: pass
        pg2 = await ctx.new_page(); await pg2.goto(B); await asyncio.sleep(0.6)
        txt = await pg2.evaluate("document.querySelector('pre') ? document.querySelector('pre').textContent : ''")
        ck("DESCONHECIDO" in txt and "Não prova falta de memória" in txt and "SAÍDA REGISTRADA" not in txt, "queda sem pagehide = DESCONHECIDO (sem afirmar OOM)")
        pg = pg2
        # schema inválido / lixo no localStorage
        for junk in ['{"cur":5}', 'nao-e-json', '{"v":2,"cur":{"boot":1,"ev":"x"}}', '[]']:
            c2 = await b.new_context(); pj = await c2.new_page(); errs = []
            pj.on("pageerror", lambda e: errs.append(str(e)))
            await pj.add_init_script("localStorage.setItem('%s', %s); localStorage.setItem('%s_on', String(Date.now()+60000));" % (K, json.dumps(junk), K))
            await pj.goto(B); await asyncio.sleep(0.4)
            raw = await pj.evaluate(f"localStorage.getItem('{K}')")
            ok = json.loads(raw).get("v") == 2 and json.loads(raw)["cur"]["ev"][0]["k"] == "boot" and not await pj.evaluate("!!document.querySelector('pre')")
            ck(ok and not errs, "dado inválido no localStorage (%s) é descartado sem erro" % junk)
            await c2.close()
        # vencido
        await pg.evaluate(f"localStorage.setItem('{K}_on', String(Date.now()-1000))")
        await pg.goto(B); await asyncio.sleep(0.4)
        s = await st(); ck(s[1] is None and not s[3], "depois de 24 h desliga sozinho")
        # ?diag=0
        await pg.goto(B + "?diag=1"); await asyncio.sleep(0.3)
        await pg.goto(B + "?diag=0"); await asyncio.sleep(0.3)
        s = await st(); ck(s[0] is None and s[1] is None and not s[3], "?diag=0 desliga e apaga o registro")
        await b.close()
    print("RESULT", "OK" if all(res) else "FALHAS=%d" % res.count(False))
    return all(res)
sys.exit(0 if asyncio.run(main()) else 1)
