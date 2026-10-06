// SDK Agora FALSO com CAPTURA REAL (getUserMedia, dispositivo sintético do Chromium) — testes de
// ciclo de vida/privacidade da ponte (auditoria R45-V01..V08). Nada de rede/RTC real.
// window.ctl permite segurar promessas (unpublish/leave/subscribe/setMuted/mic) e injetar falhas.
(function () {
  const st = window.stats = { created: 0, closes: 0, stops: 0, publish: 0, unpublish: 0, leave: 0, join: 0, play: 0 };
  const ctl = window.ctl = { hold: {}, fail: {} };
  window.raws = [];
  window.mics = [];
  function gate(name) {   // promessa controlada: fica pendente enquanto ctl.hold[name] existir
    if (ctl.fail[name]) return Promise.reject({ code: 'NETWORK_ERROR', message: name + ' failed' });
    if (!ctl.hold[name]) return Promise.resolve();
    return new Promise((ok) => { (ctl.waiters = ctl.waiters || {})[name] = ok; });
  }
  window.release = function (name) { const w = ctl.waiters && ctl.waiters[name]; delete ctl.hold[name]; if (w) { delete ctl.waiters[name]; w(); } };
  async function micTrack() {
    await gate('mic');
    const s = await navigator.mediaDevices.getUserMedia({ audio: true });
    const raw = s.getAudioTracks()[0];
    window.raws.push(raw);
    st.created++;
    const t = { kind: 'mic', raw, muted: false, closed: false, handlers: {},
      getMediaStreamTrack() { return raw; },
      play() {}, stop() { st.stops++; },
      async setMuted(m) {
        if (ctl.fail.setMuted) { throw { code: 'NETWORK_ERROR', message: 'mute failed' }; }   // falha ANTES de mudar (pior caso)
        await gate('setMuted');
        this.muted = m; raw.enabled = !m;
      },
      close() { if (!this.closed) { this.closed = true; st.closes++; raw.stop(); } },
      on(ev, cb) { this.handlers[ev] = cb; }, removeAllListeners() { this.handlers = {}; },
      getTrackLabel() { return 'Fake Mic'; } };
    window.mics.push(t);
    return t;
  }
  function remoteTrack(uid) {
    return { uid, isPlaying: false, play() { this.isPlaying = true; st.play++; }, stop() { this.isPlaying = false; } };
  }
  window.AgoraRTC = {
    VERSION: '4.24.8-fake-live', setLogLevel() {}, disableLogUpload() {}, checkSystemRequirements() { return true; },
    getMicrophones() { return Promise.resolve([]); },
    createMicrophoneAudioTrack() { return micTrack(); },
    createClient() {
      const c = { handlers: {}, joined: false, published: [],
        on(ev, cb) { this.handlers[ev] = cb; }, removeAllListeners() { this.handlers = {}; },
        async join() { st.join++; await gate('join'); this.joined = true; },
        async publish(ts) { await gate('publish'); st.publish++; this.published = ts.slice(); },
        async unpublish() { st.unpublish++; await gate('unpublish'); this.published = []; },
        async leave() { st.leave++; await gate('leave'); this.joined = false; },
        async subscribe(u) { await gate('subscribe'); u.audioTrack = remoteTrack(u.uid); return u.audioTrack; },
        enableAudioVolumeIndicator() {}, renewToken() { return Promise.resolve(); } };
      (window.clients = window.clients || []).push(c);
      window.fakeClient = c;
      return c;
    } };
  window.remoteUser = function (uid) { return { uid, audioTrack: null }; };
  window.liveCount = () => window.raws.filter((r) => r.readyState === 'live').length;
})();
