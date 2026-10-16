# R137 · Web: abre LIGAS E RANKING e clica na Liga Ouro ANTES do conteúdo extra chegar ("Carregando cenário e peças…"),
# solta o download e confere que o cenário e as peças aparecem sozinhos.
# Uso: python3 tests/web/r137_ligas_conteudo_e2e.py <build montada> <pasta das prints>
import asyncio, sys, time, subprocess
from playwright.async_api import async_playwright
S=sys.argv[1]; OUT=sys.argv[2]   # build Web montada (pasta servida) e pasta das prints
srv=subprocess.Popen([sys.executable,'-m','http.server','8766','--bind','127.0.0.1'],cwd=S,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
K=1672/1600
def P(x,y): return (x*K, y*K)
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args=['--no-proxy-server','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'])
        ctx=await b.new_context(viewport={'width':1672,'height':941})
        pg=await ctx.new_page()
        t0=time.time(); logs=[]
        pg.on('console',lambda m: logs.append('%.0f %s'%(time.time()-t0,m.text)))
        import re
        CONT=re.search(r'name="fraiha-conteudo" content="([^"]+)"',open(S+'/index.html').read()).group(1)
        hold={'on':True}
        async def slow(route):
            while hold['on']: await asyncio.sleep(0.2)
            await route.continue_()
        await pg.route(lambda u: u.endswith(CONT), slow)
        await pg.goto('http://127.0.0.1:8766/index.html')
        for i in range(240):
            await asyncio.sleep(1)
            if any('[conteudo] baixando' in l for l in logs): break
        await asyncio.sleep(3)
        await pg.mouse.click(857,783); await asyncio.sleep(4)   # JOGAR COMO CONVIDADO
        await pg.screenshot(path=OUT+'/01_home.png')
        await pg.mouse.click(710,692); await asyncio.sleep(5)   # LIGAS E RANKING
        await pg.screenshot(path=OUT+'/02_ligas.png')
        x,y=P(683,340); await pg.mouse.click(x,y); await asyncio.sleep(3)
        await pg.screenshot(path=OUT+'/A_ouro_antes.png')
        hold['on']=False
        for i in range(120):
            await asyncio.sleep(1)
            if any('[conteudo] pronto' in l for l in logs): break
        await asyncio.sleep(3)
        await pg.screenshot(path=OUT+'/B_ouro_depois_sem_clicar.png')
        for nome,(lx,ly) in {'ouro':(683,340),'challenger':(1389,340),'bronze':(447,340)}.items():
            x,y=P(lx,ly); await pg.mouse.click(x,y); await asyncio.sleep(3)
            await pg.screenshot(path=OUT+'/03_%s.png'%nome)
        print('\n'.join(l for l in logs if 'conteudo' in l or 'ERROR' in l or 'rror' in l)[-3000:])
        await b.close()
try: asyncio.run(main())
finally: srv.kill()
