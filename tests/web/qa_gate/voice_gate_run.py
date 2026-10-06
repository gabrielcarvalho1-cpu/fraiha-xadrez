import sys, json
# R45 · roda o gate de voz no Chromium com microfone FALSO (grant) e com permissão negada (deny).
URL = sys.argv[1]
from playwright.sync_api import sync_playwright
def run(mode, args, perms):
    lines, reqs = [], []
    with sync_playwright() as p:
        b = p.chromium.launch(args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"] + args)
        ctx = b.new_context(viewport={"width": 1280, "height": 720}, permissions=perms)
        pg = ctx.new_page()
        pg.on("console", lambda m: lines.append(m.text))
        pg.on("request", lambda r: reqs.append(r.url))
        pg.goto(URL + "?mode=" + mode)
        for i in range(180):
            pg.wait_for_timeout(1000)
            if any("GATE RESULT" in l for l in lines): break
        b.close()
    print("=== modo", mode)
    for l in lines:
        if l.startswith("GATE") or l.startswith("[voice]") or "rror" in l: print(l)
    sdk = [u for u in reqs if "AgoraRTC" in u or "fraiha-voice" in u]
    print("arquivos de voz pedidos:", [u.split("/")[-1] for u in sdk])
    print("SDK de CDN externo usado:", any("jsdelivr" in u for u in reqs))
    return lines
run("grant", ["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"], ["microphone"])
run("deny", ["--use-fake-device-for-media-stream", "--deny-permission-prompts"], [])
