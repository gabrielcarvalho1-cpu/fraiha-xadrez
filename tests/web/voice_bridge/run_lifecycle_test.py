"""R46 · ciclo de vida / privacidade da ponte FRAIHA Voice (auditoria Voice R45: V01, V02, V03, V04, V08).
Chromium com CAPTURA REAL (getUserMedia + dispositivo sintético) e SDK Agora FALSO (sem rede/RTC).
A prova de "microfone parado" é o MediaStreamTrack.readyState === 'ended', não o debug da ponte.
Rodar: python3 tests/web/voice_bridge/run_lifecycle_test.py"""
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


JOIN = "window.FraihaVoiceBridge.join(%d, JSON.stringify({app_id:'a', channel:'fx_ranked_x', token:'t', uid:1, muted:%s, speaker_muted:false}))"


def connect(pg, seq=1, muted="false"):
    pg.evaluate("window.FraihaVoiceBridge.bind(); window.FraihaVoiceBridge.prepare(%d)" % seq)
    pg.wait_for_function("window.events.some(e => e.ev === 'mic_ready' && e.seq === %d)" % seq, timeout=5000)
    pg.evaluate(JOIN % (seq, muted))
    pg.wait_for_function("window.events.some(e => e.ev === 'joined' && e.seq === %d)" % seq, timeout=5000)


with tempfile.TemporaryDirectory() as tmp:
    for n in ("page_live.html", "fake_agora_live.js"):
        shutil.copy(os.path.join(HERE, n), tmp)
    os.makedirs(os.path.join(tmp, "voice"))
    shutil.copy(os.path.join(REPO, "web/voice/fraiha-voice-bridge-v1.js"), os.path.join(tmp, "voice"))
    port = 28900 + os.getpid() % 300
    srv = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"], cwd=tmp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.8)
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"])

            def fresh():
                pg = b.new_page()
                pg.goto(f"http://127.0.0.1:{port}/page_live.html")
                return pg

            S = lambda pg: pg.evaluate("window.stats")
            live = lambda pg: pg.evaluate("window.liveCount()")
            evs = lambda pg, name: pg.evaluate(f"window.events.filter(e => e.ev === '{name}')")

            # --- controle: fluxo normal fecha tudo uma vez
            pg = fresh(); connect(pg)
            check(live(pg) == 1 and S(pg)["publish"] == 1, "controle: entrou, microfone capturando e publicado")
            pg.evaluate("window.FraihaVoiceBridge.leave(2, 'user')")
            pg.wait_for_function("window.events.some(e => e.ev === 'left')", timeout=5000)
            pg.wait_for_timeout(100)
            s = S(pg)
            check(live(pg) == 0 and s["closes"] == 1 and s["leave"] == 1, "controle: sair fecha a captura 1x e sai do canal 1x (%s)" % s)
            pg.close()

            # --- V01: unpublish e leave PENDURADOS (Agora travada) -> captura para NA HORA
            pg = fresh(); connect(pg)
            pg.evaluate("ctl.hold.unpublish = 1; ctl.hold.leave = 1")
            pg.evaluate("window.FraihaVoiceBridge.leave(2, 'user')")
            pg.wait_for_timeout(50)
            check(live(pg) == 0, "V01: com unpublish/leave da Agora pendurados, a captura local PARA em <50ms")
            pg.wait_for_function("window.events.some(e => e.ev === 'left')", timeout=8000)
            check(live(pg) == 0 and S(pg)["closes"] == 1, "V01: 'left' só depois da captura parada; fechada exatamente 1x")
            # nova tentativa enquanto a saída antiga ainda está pendurada não é fechada por ela
            connect(pg, 3)
            check(live(pg) == 1, "V01: entrar de novo com a saída antiga ainda pendurada funciona (mic novo vivo)")
            pg.evaluate("release('unpublish'); release('leave')"); pg.wait_for_timeout(150)
            check(live(pg) == 1 and pg.evaluate("JSON.parse(window.FraihaVoiceBridge.debug()).joined"), "V01: a saída antiga, ao destravar, NÃO fecha a tentativa nova")
            pg.evaluate("window.FraihaVoiceBridge.leave(4, 'end')"); pg.wait_for_timeout(50)
            check(live(pg) == 0, "V01: fim de partida também para a captura")
            pg.close()

            # --- V01 b: join pendurado (rede sem rota) + sair
            pg = fresh()
            pg.evaluate("window.FraihaVoiceBridge.bind(); window.FraihaVoiceBridge.prepare(1)")
            pg.wait_for_function("window.events.some(e => e.ev === 'mic_ready')", timeout=5000)
            pg.evaluate("ctl.hold.join = 1"); pg.evaluate(JOIN % (1, "false")); pg.wait_for_timeout(50)
            pg.evaluate("window.FraihaVoiceBridge.leave(2, 'cancel')"); pg.wait_for_timeout(50)
            check(live(pg) == 0, "V01: sair com o join pendurado para a captura na hora")
            pg.evaluate("release('join')"); pg.wait_for_timeout(150)
            check(live(pg) == 0 and S(pg)["publish"] == 0, "V01: join que destrava depois NÃO publica nem reabre microfone")
            pg.close()

            # --- pagehide (F5 / fechar aba)
            pg = fresh(); connect(pg)
            pg.evaluate("ctl.hold.unpublish = 1; ctl.hold.leave = 1; window.dispatchEvent(new Event('pagehide'))"); pg.wait_for_timeout(50)
            check(live(pg) == 0, "pagehide com Agora pendurada: captura parada")
            pg.close()

            # --- V03: prepare enfileirado + leave no mesmo turno -> não abre microfone
            pg = fresh()
            pg.evaluate("window.FraihaVoiceBridge.bind(); window.FraihaVoiceBridge.prepare(1); window.FraihaVoiceBridge.leave(2, 'cancel')")
            pg.wait_for_function("window.events.some(e => e.ev === 'left')", timeout=5000); pg.wait_for_timeout(300)
            check(S(pg)["created"] == 0 and live(pg) == 0 and not evs(pg, "mic_ready"), "V03: cancelar no mesmo turno não pede/abre microfone (%s)" % S(pg))
            check(pg.evaluate("JSON.parse(window.FraihaVoiceBridge.debug()).seq") == 2, "V03: geração do cancelamento prevalece (seq=2)")
            pg.close()

            # --- V03 b: permissão pendente + sair -> trilha que chega depois é fechada
            pg = fresh()
            pg.evaluate("ctl.hold.mic = 1; window.FraihaVoiceBridge.bind(); window.FraihaVoiceBridge.prepare(1)"); pg.wait_for_timeout(50)
            pg.evaluate("window.FraihaVoiceBridge.leave(2, 'cancel')"); pg.wait_for_timeout(50)
            pg.evaluate("release('mic')"); pg.wait_for_timeout(300)
            check(live(pg) == 0 and not evs(pg, "mic_ready"), "V03: microfone que chega depois do cancelamento é fechado")
            pg.close()

            # --- V03 c: setMuted inicial pendente + sair -> não publica depois
            pg = fresh()
            pg.evaluate("window.FraihaVoiceBridge.bind(); window.FraihaVoiceBridge.prepare(1)")
            pg.wait_for_function("window.events.some(e => e.ev === 'mic_ready')", timeout=5000)
            pg.evaluate("ctl.hold.setMuted = 1"); pg.evaluate(JOIN % (1, "true")); pg.wait_for_timeout(80)
            pg.evaluate("window.FraihaVoiceBridge.leave(2, 'cancel')"); pg.wait_for_timeout(50)
            pg.evaluate("release('setMuted')"); pg.wait_for_timeout(200)
            check(S(pg)["publish"] == 0 and live(pg) == 0, "V03: mute inicial pendente + sair -> nada é publicado")
            pg.close()

            # --- V02: mute rejeitado -> estado REAL, não sucesso falso
            pg = fresh(); connect(pg)
            pg.evaluate("ctl.fail.setMuted = 1; window.FraihaVoiceBridge.setMuted(true)"); pg.wait_for_timeout(150)
            m = evs(pg, "muted")
            check(m and m[-1]["muted"] is False, "V02: mute que falhou informa muted=false (estado real), não sucesso")
            check(any(e.get("code") == "MUTE_FAILED" for e in evs(pg, "error")), "V02: falha de mute vira aviso MUTE_FAILED")
            pg.close()

            # --- V02 b: entrar mudo com o mute falhando -> NÃO publica microfone aberto
            pg = fresh()
            pg.evaluate("window.FraihaVoiceBridge.bind(); window.FraihaVoiceBridge.prepare(1)")
            pg.wait_for_function("window.events.some(e => e.ev === 'mic_ready')", timeout=5000)
            pg.evaluate("ctl.fail.setMuted = 1"); pg.evaluate(JOIN % (1, "true"))
            pg.wait_for_function("window.events.some(e => e.ev === 'joined')", timeout=5000)
            j = evs(pg, "joined")[-1]
            check(S(pg)["publish"] == 0 and j["muted"] is True, "V02: preferência 'entrar mudo' + mute falhou -> entra OUVINDO, sem publicar o microfone")
            pg.evaluate("ctl.fail.setMuted = 0; window.FraihaVoiceBridge.setMuted(false)"); pg.wait_for_timeout(150)
            check(S(pg)["publish"] == 1 and evs(pg, "muted")[-1]["muted"] is False, "V02: ao desmutar por gesto, publica normalmente")
            pg.close()

            # --- V04: trilha encerrada (permissão revogada / mic removido) -> desmutar recria
            pg = fresh(); connect(pg)
            pg.evaluate("window.raws[0].stop(); window.mics[0].handlers['track-ended']()"); pg.wait_for_timeout(100)
            check(any(e.get("code") == "TRACK_ENDED" for e in evs(pg, "mic_lost")), "V04: microfone perdido avisado")
            check(not pg.evaluate("JSON.parse(window.FraihaVoiceBridge.debug()).mic"), "V04: trilha morta é descartada (não fica 'mic' fantasma)")
            pg.evaluate("window.FraihaVoiceBridge.setMuted(true)"); pg.wait_for_timeout(100)
            check(S(pg)["created"] == 1, "V04: mutar sem microfone não pede microfone novo")
            pg.evaluate("window.FraihaVoiceBridge.setMuted(false)"); pg.wait_for_timeout(200)
            s = S(pg)
            check(s["created"] == 2 and live(pg) == 1 and s["publish"] == 2 and evs(pg, "muted")[-1]["muted"] is False,
                  "V04: desmutar (gesto) recria e publica a trilha nova (%s)" % s)
            pg.evaluate("window.FraihaVoiceBridge.leave(2, 'user')"); pg.wait_for_timeout(50)
            check(live(pg) == 0, "V04: sair fecha a trilha recriada")
            pg.close()

            # --- V08: subscribe atrasado de quem já saiu não ressuscita o participante
            pg = fresh(); connect(pg)
            pg.evaluate("ctl.hold.subscribe = 1; window.u2 = remoteUser(2); fakeClient.handlers['user-joined'](u2); fakeClient.handlers['user-published'](u2, 'audio'); 0")
            pg.wait_for_timeout(50)
            pg.evaluate("fakeClient.handlers['user-left'](u2)"); pg.wait_for_timeout(50)
            pg.evaluate("release('subscribe')"); pg.wait_for_timeout(150)
            d = pg.evaluate("JSON.parse(window.FraihaVoiceBridge.debug())")
            check(d["remotes"] == [] and S(pg)["play"] == 0, "V08: participante que saiu não volta e o áudio atrasado não toca (%s)" % d["remotes"])
            pg.close()
            b.close()
    finally:
        srv.terminate()
print("RESULT", "OK" if fails == 0 else "FALHAS=%d" % fails)
sys.exit(1 if fails else 0)
