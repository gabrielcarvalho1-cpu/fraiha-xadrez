/* FRAIHA Voice v1 · ponte Godot <-> Agora Web SDK (só ÁUDIO).
 * O jogo (Godot) nunca fala com a Agora direto: chama window.FraihaVoiceBridge e recebe eventos
 * por UMA função de callback com UMA string JSON (o JavaScriptBridge do Godot só passa tipos simples).
 * Não guarda nem envia segredo: o token curto vem do servidor FRAIHA. Não grava áudio.
 * Toda operação carrega um "seq": quando o Godot sai (leave) ou começa outra tentativa, o seq muda
 * e qualquer passo atrasado da tentativa antiga se desfaz sozinho (sem microfone "preso" ligado).
 * PRIVACIDADE (auditoria R45-V01): sair/fim/F5/erro PARA A CAPTURA LOCAL NA HORA (stop+close da
 * trilha, síncrono). unpublish/leave da Agora vêm DEPOIS, em segundo plano e com tempo limite —
 * a rede nunca segura o microfone aberto. Toda espera de rede/permissão é cancelável pelo seq. */
(function () {
  'use strict';
  if (window.FraihaVoiceBridge) return;
  var SDK_LOCAL = 'voice/AgoraRTC_N-4.24.8.js';
  var SDK_CDN = 'https://cdn.jsdelivr.net/npm/agora-rtc-sdk-ng@4.24.8/AgoraRTC_N-production.js';
  var cb = null;            // window.FraihaVoiceCb (Godot)
  var cur = 0;              // seq atual (o Godot é o dono)
  var chain = Promise.resolve();
  var sdkPromise = null;
  var client = null, mic = null, published = false, muted = false;
  var remotes = {};         // uid -> {audio: track|null}
  var autoplayBlocked = false;
  // ÁUDIO RECEBIDO (alto-falante da voz), independente do microfone e dos sons do jogo:
  // speakerMuted = não toca NINGUÉM; mutedUids = silencia só aquele participante (salas com 3+ humanos).
  // Continua inscrito no canal (voltar a ouvir é imediato); o microfone não é tocado.
  var speakerMuted = false;
  var mutedUids = {};
  function audible(uid) { return !speakerMuted && !mutedUids[uid]; }
  function applyRemote(uid) {
    var r = remotes[uid]; if (!r || !r.audio) return;
    try { if (audible(uid)) { if (!r.audio.isPlaying) r.audio.play(); } else if (r.audio.isPlaying) r.audio.stop(); } catch (e) {}
  }
  function applyAll() { Object.keys(remotes).forEach(applyRemote); }

  function emit(ev, data) {
    var o = data || {};
    o.ev = ev;
    o.seq = o.seq === undefined ? cur : o.seq;
    try { if (cb) cb(JSON.stringify(o)); } catch (e) { /* Godot ocupado: ignora */ }
  }
  function errCode(e) {
    var c = e && (e.code || e.name) ? String(e.code || e.name) : 'UNKNOWN';
    if (c === 'NotAllowedError' || c === 'SecurityError') return 'PERMISSION_DENIED';
    if (c === 'NotFoundError' || c === 'OverconstrainedError') return 'DEVICE_NOT_FOUND';
    if (c === 'NotReadableError' || c === 'AbortError') return 'NOT_READABLE';
    if (c === 'NotSupportedError') return 'NOT_SUPPORTED';
    return c;
  }
  function errMsg(e) { return String((e && e.message) || e || '').slice(0, 160); }
  function stale(seq) { return seq !== cur; }
  function serial(fn) { var p = chain.then(fn, fn); chain = p.catch(function () {}); return p; }

  // ---- geração / cancelamento (R45-V03): o seq muda NA CHAMADA, e toda espera pendente da
  // tentativa antiga é liberada na hora com CANCEL (a fila nunca fica presa numa promessa da Agora).
  var CANCEL = { cancelled: true };
  var waiters = [];
  function setCur(seq) {
    cur = seq;
    var keep = [];
    waiters.forEach(function (w) { if (w.seq !== cur) w.done(CANCEL); else keep.push(w); });
    waiters = keep;
  }
  function until(p, seq) {   // espera p OU o cancelamento da tentativa seq (o que vier primeiro)
    if (stale(seq)) { Promise.resolve(p).catch(function () {}); return Promise.resolve(CANCEL); }
    return new Promise(function (ok, fail) {
      var w = { seq: seq, done: ok };
      waiters.push(w);
      var off = function () { waiters = waiters.filter(function (x) { return x !== w; }); };
      Promise.resolve(p).then(function (v) { off(); ok(v); }, function (e) { off(); fail(e); });
    });
  }
  function bounded(p, ms) {  // rede em segundo plano: nunca espera para sempre
    return new Promise(function (ok) {
      var t = setTimeout(ok, ms);
      Promise.resolve(p).then(function () { clearTimeout(t); ok(); }, function () { clearTimeout(t); ok(); });
    });
  }
  // Para a CAPTURA local já (idempotente). Também para a MediaStreamTrack crua, por garantia.
  function killMic(m) {
    if (!m || m.__fxKilled) return;
    m.__fxKilled = true;
    try { m.removeAllListeners && m.removeAllListeners(); } catch (e) {}
    try { m.stop(); } catch (e) {}
    try { m.close(); } catch (e) {}
    try { var raw = m.getMediaStreamTrack && m.getMediaStreamTrack(); if (raw && raw.readyState !== 'ended') raw.stop(); } catch (e) {}
  }
  function trackMuted(m) { try { return !!m.muted; } catch (e) { return false; } }

  function loadScript(src, ms) {
    return new Promise(function (ok, fail) {
      var s = document.createElement('script');
      var t = setTimeout(function () { s.onload = s.onerror = null; fail(new Error('timeout ' + src)); }, ms);
      s.src = src; s.async = true;
      s.onload = function () { clearTimeout(t); ok(); };
      s.onerror = function () { clearTimeout(t); fail(new Error('load ' + src)); };
      document.head.appendChild(s);
    });
  }
  function sdk() {
    if (window.AgoraRTC) return Promise.resolve(window.AgoraRTC);
    if (sdkPromise) return sdkPromise;
    emit('sdk_loading');
    sdkPromise = loadScript(SDK_LOCAL, 20000).catch(function () { return loadScript(SDK_CDN, 20000); }).then(function () {
      var A = window.AgoraRTC;
      if (!A) throw new Error('sdk_missing');
      try { A.setLogLevel(3); } catch (e) {}        // só avisos/erros no console
      try { A.disableLogUpload(); } catch (e) {}    // sem envio de logs para a Agora
      A.onAutoplayFailed = function () {
        autoplayBlocked = true;
        emit('autoplay_blocked');
        var resume = function () {
          document.removeEventListener('pointerdown', resume, true);
          document.removeEventListener('keydown', resume, true);
          autoplayBlocked = false;
          applyAll();
          emit('autoplay_ok');
        };
        document.addEventListener('pointerdown', resume, true);
        document.addEventListener('keydown', resume, true);
      };
      A.onMicrophoneChanged = function (info) {
        // microfone novo/removido: se o atual saiu, troca para o padrão do sistema
        emit('device_changed', { state: String(info && info.state || '') });
        if (!mic) return;
        var label = '';
        try { label = mic.getTrackLabel(); } catch (e) {}
        if (info && info.state === 'INACTIVE' && info.device && info.device.label === label) {
          A.getMicrophones().then(function (list) {
            if (mic && list && list.length) return mic.setDevice(list[0].deviceId);
          }).catch(function (e) { emit('mic_lost', { code: errCode(e), message: errMsg(e) }); });
        }
      };
      emit('sdk_ready', { version: String(A.VERSION || '') });
      return A;
    });
    sdkPromise.catch(function () { sdkPromise = null; });
    return sdkPromise;
  }

  function supportInfo() {
    if (!window.isSecureContext) return { ok: false, reason: 'insecure' };
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return { ok: false, reason: 'no_media' };
    if (!window.RTCPeerConnection) return { ok: false, reason: 'no_webrtc' };
    return { ok: true, reason: '' };
  }

  function remoteList() {
    return Object.keys(remotes).map(Number).sort(function (a, b) { return a - b; });
  }

  // 1º (síncrono): captura local parada, áudio recebido parado, estado zerado.
  // 2º (segundo plano, com limite): unpublish + leave na Agora. Devolve a promessa da parte de rede.
  function teardown() {
    var c = client, m = mic, rs = remotes;
    client = null; mic = null; published = false; remotes = {}; mutedUids = {};
    killMic(m);
    Object.keys(rs).forEach(function (u) { try { if (rs[u] && rs[u].audio) rs[u].audio.stop(); } catch (e) {} });
    if (!c) return Promise.resolve();
    try { c.removeAllListeners(); } catch (e) {}
    return (async function () {
      if (m) await bounded(c.unpublish(), 2000);
      await bounded(c.leave(), 5000);
    })();
  }

  // Trilha encerrada (permissão revogada / microfone removido) — R45-V04: é DESCARTADA (fechada,
  // despublicada em segundo plano). Só volta a existir num gesto explícito (desmutar).
  function onTrackEnded(t) {
    if (mic !== t) { killMic(t); return; }
    var c = client;
    mic = null;
    killMic(t);
    if (c && published) { published = false; bounded(c.unpublish([t]), 2000); }
    emit('mic_lost', { code: 'TRACK_ENDED', message: 'microfone desconectado ou permissão revogada' });
  }
  async function makeMic(A) {
    var t = await A.createMicrophoneAudioTrack({ encoderConfig: 'speech_standard', AEC: true, ANS: true, AGC: true });
    t.on('track-ended', function () { onTrackEnded(t); });
    return t;
  }
  // Cria a trilha para a tentativa seq; se a tentativa foi cancelada enquanto o navegador pedia
  // permissão, a trilha que chegar atrasada é fechada (nunca fica capturando).
  async function micFor(A, seq) {
    var tp = makeMic(A);
    tp.then(function (t) { if (stale(seq)) killMic(t); }, function () {});
    var t = await until(tp, seq);
    if (t === CANCEL || stale(seq)) { if (t && t !== CANCEL) killMic(t); return CANCEL; }
    return t;
  }

  // 1) suporte + contexto seguro + SDK + permissão + dispositivo + trilha (antes do token)
  function prepare(seq) {
    setCur(seq);   // a geração muda NA CHAMADA (um leave posterior no mesmo turno prevalece)
    return serial(async function () {
      if (stale(seq)) return;
      var sup = supportInfo();
      if (!sup.ok) return emit('error', { seq: seq, stage: 'support', code: sup.reason });
      var A;
      try { A = await until(sdk(), seq); } catch (e) { return stale(seq) || emit('error', { seq: seq, stage: 'sdk', code: 'SDK_LOAD', message: errMsg(e) }); }
      if (A === CANCEL || stale(seq)) return;
      try { if (!A.checkSystemRequirements()) return emit('error', { seq: seq, stage: 'support', code: 'unsupported' }); } catch (e) {}
      if (!mic) {
        emit('permission', { seq: seq });
        var t;
        try { t = await micFor(A, seq); } catch (e) { return stale(seq) || emit('error', { seq: seq, stage: 'mic', code: errCode(e), message: errMsg(e) }); }
        if (t === CANCEL) return;
        mic = t;
      }
      emit('mic_ready', { seq: seq, label: (function () { try { return mic.getTrackLabel(); } catch (e) { return ''; } })() });
    });
  }

  // 2) token (do servidor) -> join -> publish -> listeners
  function join(seq, cfgJson) {
    return serial(async function () {
      if (stale(seq)) return;
      var cfg = JSON.parse(cfgJson);
      speakerMuted = !!cfg.speaker_muted;   // estado do alto-falante vem do jogo a cada entrada
      var A = window.AgoraRTC;
      if (!A || !mic) return emit('error', { seq: seq, stage: 'join', code: 'NOT_PREPARED' });
      if (client) { var keep = mic; mic = null; teardown(); mic = keep && !keep.__fxKilled ? keep : null; }
      if (!mic) {
        var nt;
        try { nt = await micFor(A, seq); } catch (e) { return stale(seq) || emit('error', { seq: seq, stage: 'mic', code: errCode(e), message: errMsg(e) }); }
        if (nt === CANCEL) return;
        mic = nt;
      }
      var c = A.createClient({ mode: 'rtc', codec: 'vp8' });
      client = c;
      c.on('connection-state-change', function (now, prev, reason) {
        if (client !== c) return;
        emit('state', { seq: seq, now: String(now), prev: String(prev), reason: String(reason || '') });
      });
      // R45-V08: cada participante tem uma geração; saiu/despublicou → um subscribe atrasado é descartado
      var rgen = {};
      var bump = function (uid) { rgen[uid] = (rgen[uid] || 0) + 1; var r = remotes[uid]; if (r && r.audio) { try { r.audio.stop(); } catch (e) {} } };
      c.on('user-joined', function (u) { if (client !== c) return; if (!remotes[u.uid]) remotes[u.uid] = { audio: null }; emit('remote', { seq: seq, uids: remoteList() }); });
      c.on('user-left', function (u) { if (client !== c) return; bump(u.uid); delete remotes[u.uid]; emit('remote', { seq: seq, uids: remoteList() }); });
      c.on('user-published', async function (u, kind) {
        if (client !== c || kind !== 'audio') return;   // v1: só áudio (vídeo nunca é assinado)
        var g = rgen[u.uid] || 0;
        try {
          await c.subscribe(u, 'audio');
          if (client !== c || (rgen[u.uid] || 0) !== g) { try { if (u.audioTrack) u.audioTrack.stop(); } catch (e) {} return; }
          remotes[u.uid] = { audio: u.audioTrack };
          applyRemote(u.uid);   // respeita "voz recebida mutada" (geral ou só desse participante)
          emit('remote', { seq: seq, uids: remoteList() });
        } catch (e) { emit('warn', { seq: seq, code: errCode(e), message: errMsg(e) }); }
      });
      c.on('user-unpublished', function (u, kind) { if (client !== c || kind !== 'audio') return; bump(u.uid); if (remotes[u.uid]) remotes[u.uid].audio = null; });
      c.on('token-privilege-will-expire', function () { if (client === c) emit('will_expire', { seq: seq }); });
      c.on('token-privilege-did-expire', function () { if (client === c) emit('expired', { seq: seq }); });
      c.on('volume-indicator', function (list) {
        if (client !== c) return;
        var talk = [];
        (list || []).forEach(function (v) { if (v.level >= 8) talk.push(Number(v.uid)); });
        emit('speaking', { seq: seq, uids: talk });
      });
      c.on('exception', function (ev) { if (client === c) emit('warn', { seq: seq, code: String(ev && ev.code || ''), message: String(ev && ev.msg || '').slice(0, 120) }); });
      var r;
      try {
        r = await until(c.join(cfg.app_id, cfg.channel, cfg.token, Number(cfg.uid)), seq);
      } catch (e) {
        if (client === c) teardown();
        return stale(seq) || emit('error', { seq: seq, stage: 'join', code: errCode(e), message: errMsg(e) });
      }
      if (r === CANCEL || stale(seq) || client !== c) { bounded(c.leave(), 5000); return; }
      try { c.enableAudioVolumeIndicator(); } catch (e) {}
      // R45-V02: "entrar mudo" só publica se o mute foi REALMENTE aplicado; se falhar, entra só ouvindo
      var want = !!cfg.muted, okMute = true;
      try { if (await until(mic.setMuted(want), seq) === CANCEL) return; } catch (e) { okMute = false; }
      if (stale(seq) || client !== c || !mic) return;
      var real = trackMuted(mic);
      if (want && (!okMute || !real)) {
        muted = true;
        emit('joined', { seq: seq, muted: true, uids: remoteList() });
        return emit('error', { seq: seq, stage: 'mute', code: 'MUTE_FAILED', message: 'não foi possível entrar mudo; microfone não enviado', soft: true });
      }
      muted = real;
      try { if (await until(c.publish([mic]), seq) === CANCEL) return; published = true; }
      catch (e) {
        teardown();
        return stale(seq) || emit('error', { seq: seq, stage: 'publish', code: errCode(e), message: errMsg(e) });
      }
      if (stale(seq) || client !== c) { teardown(); return; }
      emit('joined', { seq: seq, muted: muted, uids: remoteList() });
    });
  }

  function leave(seq, reason) {
    setCur(seq);   // invalida e LIBERA toda espera da tentativa antiga, antes da fila
    // captura parada AGORA (síncrono); a saída da Agora segue em segundo plano com limite.
    // Também aborta um join pendurado: o SDK rejeita o join em andamento (OPERATION_ABORTED).
    teardown();
    return serial(async function () {
      teardown();   // algo que a fila tenha criado entre a chamada e aqui (nada esperado)
      emit('left', { seq: seq, reason: String(reason || '') });
    });
  }

  // Microfone (envio). R45-V02: o evento 'muted' traz o estado REAL da trilha; falha vira MUTE_FAILED.
  // R45-V04: sem trilha (perdida) e desmutando = gesto explícito → recria e publica.
  function setMuted(on) {
    var seq = cur;
    return serial(async function () {
      if (stale(seq)) return;
      var want = !!on;
      if (!mic) {
        if (!want && client && window.AgoraRTC) {
          var t;
          try { t = await micFor(window.AgoraRTC, seq); }
          catch (e) { muted = true; emit('error', { stage: 'mic', code: errCode(e), message: errMsg(e), soft: true }); return emit('muted', { muted: true }); }
          if (t === CANCEL || !client) { killMic(t); return; }
          mic = t;
        } else {
          muted = want || !client;   // sem trilha nada é enviado: estado real é mudo
          return emit('muted', { muted: muted });
        }
      }
      var ok = true;
      try { if (await until(mic.setMuted(want), seq) === CANCEL) return; } catch (e) { ok = false; }
      if (stale(seq) || !mic) return;
      muted = trackMuted(mic);
      var failed = !ok || muted !== want;
      if (!muted && client && !published) {   // entrou só ouvindo (mute inicial falhou / trilha recriada)
        try { if (await until(client.publish([mic]), seq) === CANCEL) return; published = true; }
        catch (e) { emit('error', { stage: 'publish', code: errCode(e), message: errMsg(e), soft: true }); }
      }
      emit('muted', { muted: muted });
      if (failed) emit('error', { stage: 'mute', code: 'MUTE_FAILED', message: 'não foi possível ' + (want ? 'mutar' : 'desmutar') + ' o microfone', soft: true });
    });
  }

  // Alto-falante da voz: on = não ouvir ninguém (continua na sala, microfone intocado).
  function setSpeakerMuted(on) { speakerMuted = !!on; applyAll(); emit('speaker', { muted: speakerMuted, uids: mutedList() }); }
  // Mute LOCAL de um participante (só eu deixo de ouvi-lo; ninguém mais é afetado).
  function setRemoteMuted(uid, on) {
    uid = Number(uid); if (!(uid > 0)) return;
    if (on) mutedUids[uid] = true; else delete mutedUids[uid];
    applyRemote(uid); emit('speaker', { muted: speakerMuted, uids: mutedList() });
  }
  function mutedList() { return Object.keys(mutedUids).map(Number).sort(function (a, b) { return a - b; }); }
  function playingList() { return Object.keys(remotes).filter(function (u) { var r = remotes[u]; return r && r.audio && r.audio.isPlaying; }).map(Number); }

  function renew(token) {
    return serial(async function () {
      if (!client) return;
      try { await client.renewToken(String(token)); emit('renewed'); }
      catch (e) { emit('error', { stage: 'renew', code: errCode(e), message: errMsg(e), soft: true }); }
    });
  }

  // F5 / fechar aba: sai do canal e solta o microfone
  window.addEventListener('pagehide', function () { setCur(-1); teardown(); });

  window.FraihaVoiceBridge = {
    version: 1,
    bind: function () { cb = typeof window.FraihaVoiceCb === 'function' ? window.FraihaVoiceCb : null; return cb ? 1 : 0; },
    support: function () { return JSON.stringify(supportInfo()); },
    prepare: function (seq) { prepare(Number(seq)); return 1; },
    join: function (seq, cfg) { join(Number(seq), String(cfg)); return 1; },
    leave: function (seq, reason) { leave(Number(seq), reason); return 1; },
    setMuted: function (on) { setMuted(!!on); return 1; },
    renew: function (token) { renew(token); return 1; },
    setSpeakerMuted: function (on) { setSpeakerMuted(!!on); return 1; },
    setRemoteMuted: function (uid, on) { setRemoteMuted(uid, !!on); return 1; },
    debug: function () { return JSON.stringify({ seq: cur, joined: !!client, mic: !!mic, published: published, muted: muted, speakerMuted: speakerMuted, mutedUids: mutedList(), playing: playingList(), remotes: remoteList(), autoplayBlocked: autoplayBlocked, sdk: !!window.AgoraRTC }); }
  };
})();
