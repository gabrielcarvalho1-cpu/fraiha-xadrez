import sys
URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:28777/index.html"
from playwright.sync_api import sync_playwright
lines=[]
with sync_playwright() as p:
    b=p.chromium.launch(args=["--use-gl=swiftshader","--enable-unsafe-swiftshader"])
    pg=b.new_page(viewport={"width":1280,"height":720})
    pg.on("console", lambda m: lines.append(m.text))
    pg.goto(URL)
    for i in range(240):
        pg.wait_for_timeout(1000)
        if any("GATE RESULT" in l for l in lines): break
    b.close()
for l in lines:
    if l.startswith("GATE") or "ENGINE" in l or "FAIR PLAY" in l or "rror" in l: print(l)
