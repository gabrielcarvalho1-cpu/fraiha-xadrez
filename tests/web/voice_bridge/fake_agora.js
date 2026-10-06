// SDK Agora FALSO (só teste da ponte): registra cada chamada; nada de rede/áudio real.
(function () {
  const log = window.fakeLog = [];
  function track(kind, uid) {
    return { kind, uid, isPlaying: false, muted: false, closed: false, handlers: {},
      play() { this.isPlaying = true; log.push(['play', uid]); },
      stop() { this.isPlaying = false; log.push(['stop', uid]); },
      setMuted(m) { this.muted = m; log.push(['mic.setMuted', m]); return Promise.resolve(); },
      close() { this.closed = true; log.push(['mic.close']); },
      on(ev, cb) { this.handlers[ev] = cb; }, removeAllListeners() { this.handlers = {}; log.push(['mic.removeAllListeners']); },
      getTrackLabel() { return 'Fake Mic'; } };
  }
  window.AgoraRTC = {
    VERSION: '4.24.8-fake', setLogLevel() {}, disableLogUpload() {}, checkSystemRequirements() { return true; },
    getMicrophones() { return Promise.resolve([]); },
    createMicrophoneAudioTrack() { const t = track('mic', 0); window.fakeMic = t; return Promise.resolve(t); },
    createClient() {
      const c = window.fakeClient = { handlers: {}, joined: false,
        on(ev, cb) { this.handlers[ev] = cb; }, removeAllListeners() { this.handlers = {}; log.push(['client.removeAllListeners']); },
        join(app, ch, tok, uid) { this.joined = true; log.push(['join', ch, uid]); return Promise.resolve(uid); },
        publish(ts) { log.push(['publish', ts.length]); return Promise.resolve(); },
        unpublish() { log.push(['unpublish']); return Promise.resolve(); },
        leave() { this.joined = false; log.push(['leave']); return Promise.resolve(); },
        subscribe(u) { u.audioTrack = track('remote', u.uid); return Promise.resolve(u.audioTrack); },
        enableAudioVolumeIndicator() {}, renewToken() { return Promise.resolve(); } };
      return c;
    } };
  window.remoteUser = function (uid) { return { uid, audioTrack: null }; };
})();
