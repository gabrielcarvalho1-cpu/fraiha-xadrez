"""R90 · Campo de chat da Web no celular (ui_v022/web_text_field.gd, modo CHAT) num Chromium real com toque.
Usa o MESMO JavaScript do .gd (extraído do arquivo) e confere, emulando iPhone e Android:
tocar no campo foca e encaixa a barra EMBAIXO, logo acima do teclado (R151; antes no topo); digitar e APAGAR texto; tocar ENVIAR envia SEM tirar o foco
(teclado continua aberto, nada pula); várias mensagens seguidas; um toque = um envio só; Enter envia;
tocar fora solta a barra; mouse (PC) também envia.
Rodar: python3 tests/web/chat_field_e2e.py   · sai com 1 se algum FAIL."""
import asyncio, json, os, re, sys
from playwright.async_api import async_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
gd = open(os.path.join(HERE, "../../ui_v022/web_text_field.gd"), encoding="utf-8").read()
js = re.search(r'JavaScriptBridge\.eval\("""(.*?)""" %', gd, re.S).group(1)
vals = [json.dumps("fraiha-text-1"), "true", json.dumps("text"), "200", json.dumps("Mensagem para todos…")]
# R91 · o texto passa pelo operador % do GDScript: um "%" solto (ex.: "100%") quebra a formatação no jogo e o
# campo nunca é criado. Aqui a montagem segue a mesma regra (%s, %d e %% apenas) e reprova qualquer outro.
bad = re.findall(r'%(?![sd])', js.replace('%%', ''))
FORMAT_OK = not bad
parts = re.split(r'(%s|%d|%%)', js); out = []; i = 0
for p in parts:
    if p in ("%s", "%d"): out.append(vals[i]); i += 1
    elif p == "%%": out.append("%")
    else: out.append(p)
js = "".join(out)
PAGE = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;overflow:hidden;background:#222}#canvas{position:fixed;inset:0;background:#3a2a1a}</style></head>
<body><div id="canvas"></div><script>""" + js + """
const el = document.getElementById('fraiha-text-1');
// o Godot posicionaria o campo sobre o LineEdit, embaixo da tela:
Object.assign(el.style, {display:'block', left:'20px', top:'560px', width:'250px', height:'44px'});
window.sends = 0; window.blurs = 0;
new MutationObserver(() => { if (el.dataset.submit === '1') { window.sends++; window.lastText = el.value; el.dataset.submit=''; el.value=''; } })
  .observe(el, {attributes: true, attributeFilter: ['data-submit']});
el.addEventListener('blur', () => window.blurs++);
</script></body></html>"""
res = []
def ck(ok, label): res.append(bool(ok)); print("PASS" if ok else "FAIL", label)

async def run(p, name, opts):
    b = await p.chromium.launch(args=["--no-proxy-server"])
    ctx = await b.new_context(**opts)
    pg = await ctx.new_page()
    await pg.set_content(PAGE)
    st = lambda: pg.evaluate("""() => { const el=document.getElementById('fraiha-text-1'), bar=document.getElementById('fraiha-text-1-bar');
        const r=el.getBoundingClientRect(), s=bar.querySelector('button').getBoundingClientRect();
        return {focus: document.activeElement===el, docked: el.dataset.docked==='1', bar: getComputedStyle(bar).display, top: r.top,
                value: el.value, sends: window.sends, last: window.lastText||'', blurs: window.blurs, send: [s.x+s.width/2, s.y+s.height/2], vh: (window.visualViewport||window).height, bar_bottom: bar.getBoundingClientRect().bottom}; }""")
    touch = opts.get("has_touch")
    tap = (lambda x, y: pg.touchscreen.tap(x, y)) if touch else (lambda x, y: pg.mouse.click(x, y))
    await tap(140, 582); await asyncio.sleep(0.12)
    s0 = await st()
    ck(s0["focus"] and s0["docked"] and s0["top"] < 40, f"{name}: logo ao tocar o campo vai para o topo (o iPhone não rola a página) (top={s0['top']:.0f})")
    await asyncio.sleep(0.8)
    s = await st()
    ck(s["focus"] and s["docked"] and s["bar"] == "flex" and s["top"] > s["vh"] - 80 and abs(s["bar_bottom"] - s["vh"]) < 3, f"{name}: tocar no campo foca e encaixa a barra EMBAIXO, colada no teclado (top={s['top']:.0f}, tela={s['vh']:.0f})")
    if os.environ.get("SHOT_DIR"): await pg.screenshot(path=os.path.join(os.environ["SHOT_DIR"], "chat_barra_" + name.split()[0] + ".png"))
    await pg.keyboard.type("olá mundo!!"); await asyncio.sleep(0.05)
    for _ in range(2): await pg.keyboard.press("Backspace")
    s = await st(); ck(s["value"] == "olá mundo", f"{name}: digitar e apagar ('{s['value']}')")
    await tap(*s["send"]); await asyncio.sleep(0.25)
    s = await st()
    ck(s["sends"] == 1 and s["last"] == "olá mundo", f"{name}: ENVIAR manda a mensagem (envios={s['sends']})")
    ck(s["focus"] and s["blurs"] == 0 and s["docked"], f"{name}: depois do ENVIAR o campo continua focado (teclado aberto, nada pula)")
    await asyncio.sleep(0.45)
    await pg.keyboard.type("segunda"); await tap(*s["send"]); await asyncio.sleep(0.5)
    await pg.keyboard.type("terceira"); await tap(*s["send"]); await asyncio.sleep(0.25)
    s = await st(); ck(s["sends"] == 3 and s["last"] == "terceira" and s["blurs"] == 0, f"{name}: três mensagens seguidas, um envio por toque (envios={s['sends']})")
    await asyncio.sleep(0.45)
    await pg.keyboard.type("pelo enter"); await pg.keyboard.press("Enter"); await asyncio.sleep(0.2)
    s = await st(); ck(s["sends"] == 4 and s["last"] == "pelo enter", f"{name}: Enter do teclado envia")
    await tap(150, 400); await asyncio.sleep(0.3)
    s = await st(); ck(not s["focus"] and not s["docked"] and s["bar"] == "none", f"{name}: tocar fora fecha o teclado e solta a barra")
    await tap(140, 582); await asyncio.sleep(0.9)
    s = await st(); ck(s["focus"] and s["docked"], f"{name}: tocar de novo no campo volta a abrir")
    await b.close()

async def main():
    ck(FORMAT_OK, "o JavaScript do campo passa pela formatação % do GDScript (sem '%' solto)")
    async with async_playwright() as p:
        iphone = dict(p.devices["iPhone 13"]); iphone.pop("default_browser_type", None)
        pixel = dict(p.devices["Pixel 7"]); pixel.pop("default_browser_type", None)
        await run(p, "iPhone", iphone)
        await run(p, "Android", pixel)
        await run(p, "PC (mouse)", {"viewport": {"width": 1280, "height": 720}})
    print("RESULT %d/%d %s" % (sum(res), len(res), "OK" if all(res) else "FAIL"))
    sys.exit(0 if all(res) else 1)
asyncio.run(main())
