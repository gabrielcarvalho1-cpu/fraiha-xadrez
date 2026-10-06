"""R46 · ponte FRAIHA Voice no Chromium com SDK Agora FALSO: áudio recebido x microfone x sair.
Rodar: python3 tests/web/voice_bridge/run_test.py"""
import os, shutil, subprocess, sys, tempfile, time
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../../.."))
fails = 0


def check(ok, label):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        fails += 1


with tempfile.TemporaryDirectory() as tmp:
    shutil.copy(os.path.join(HERE, "page.html"), tmp)
    shutil.copy(os.path.join(HERE, "fake_agora.js"), tmp)
    os.makedirs(os.path.join(tmp, "voice"))
    shutil.copy(os.path.join(REPO, "web/voice/fraiha-voice-bridge-v1.js"), os.path.join(tmp, "voice"))
    port = 28600 + os.getpid() % 300
    srv = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"], cwd=tmp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.8)
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"])
            pg = b.new_page()
            pg.goto(f"http://127.0.0.1:{port}/page.html")
            ev = lambda name: pg.evaluate(f"window.events.filter(e => e.ev === '{name}').length")
            dbg = lambda: pg.evaluate("JSON.parse(window.FraihaVoiceBridge.debug())")
            log = lambda: pg.evaluate("window.fakeLog")
            pg.evaluate("window.FraihaVoiceBridge.bind(); window.FraihaVoiceBridge.prepare(1)")
            pg.wait_for_function("window.events.some(e => e.ev === 'mic_ready')", timeout=5000)
            pg.evaluate("""window.FraihaVoiceBridge.join(1, JSON.stringify({app_id:'a', channel:'fx_ranked_x', token:'t', uid:1, muted:false, speaker_muted:false}))""")
            pg.wait_for_function("window.events.some(e => e.ev === 'joined')", timeout=5000)
            # B (uid 2) e C (uid 3) publicam áudio
            pg.evaluate("window.fakeClient.handlers['user-published'](window.u2 = remoteUser(2), 'audio'); window.fakeClient.handlers['user-published'](window.u3 = remoteUser(3), 'audio')")
            pg.wait_for_timeout(200)
            d = dbg()
            check(sorted(d["playing"]) == [2, 3], "A ouve B e C (tocando: %s)" % d["playing"])
            # A muta só o microfone
            pg.evaluate("window.FraihaVoiceBridge.setMuted(true)"); pg.wait_for_timeout(100)
            d = dbg()
            check(d["muted"] and sorted(d["playing"]) == [2, 3] and pg.evaluate("window.fakeMic.muted"), "A muta o MICROFONE: B não ouve A, A continua ouvindo B e C")
            pg.evaluate("window.FraihaVoiceBridge.setMuted(false)"); pg.wait_for_timeout(100)
            check(not pg.evaluate("window.fakeMic.muted"), "A desmuta o microfone: B volta a ouvir A")
            # A muta só o áudio recebido
            pg.evaluate("window.FraihaVoiceBridge.setSpeakerMuted(true)")
            d = dbg()
            check(d["speakerMuted"] and d["playing"] == [] and d["joined"] and not d["muted"] and not pg.evaluate("window.fakeMic.muted"),
                  "A muta o ÁUDIO RECEBIDO: não ouve ninguém, segue na sala, microfone aberto (B ouve A)")
            # alguém publica enquanto mutado → não toca
            pg.evaluate("window.fakeClient.handlers['user-published'](remoteUser(4), 'audio')"); pg.wait_for_timeout(150)
            check(dbg()["playing"] == [], "quem entra enquanto a voz recebida está muda NÃO toca")
            pg.evaluate("window.FraihaVoiceBridge.setSpeakerMuted(false)")
            check(sorted(dbg()["playing"]) == [2, 3, 4], "A reativa: volta a ouvir todos")
            # mute LOCAL só de B
            pg.evaluate("window.FraihaVoiceBridge.setRemoteMuted(2, true)")
            d = dbg()
            check(sorted(d["playing"]) == [3, 4] and d["mutedUids"] == [2], "A silencia só B: continua ouvindo C (sem afetar ninguém)")
            pg.evaluate("window.FraihaVoiceBridge.setRemoteMuted(2, false)")
            check(sorted(dbg()["playing"]) == [2, 3, 4], "A volta a ouvir B")
            # sair
            pg.evaluate("window.FraihaVoiceBridge.leave(2, 'user')")
            pg.wait_for_function("window.events.some(e => e.ev === 'left')", timeout=5000)
            d, L = dbg(), log()
            check(not d["joined"] and not d["mic"] and d["remotes"] == [] and d["mutedUids"] == [], "SAIR: fora do canal, sem trilha, sem participantes")
            names = [x[0] for x in L]
            check(all(k in names for k in ["unpublish", "mic.close", "leave", "client.removeAllListeners"]), "SAIR: unpublish + close do microfone + leave + listeners removidos")
            b.close()
    finally:
        srv.terminate()
print("RESULT", "OK" if fails == 0 else "FALHAS=%d" % fails)
sys.exit(1 if fails else 0)
