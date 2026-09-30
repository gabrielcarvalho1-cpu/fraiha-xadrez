'use strict';
// Presença pública (offline / online / in_match) calculada SÓ pelo servidor.
// Fontes: sessões autenticadas (backend.online), último sinal válido de cada socket (qualquer mensagem
// do cliente, inclusive o "ping" que ele já envia a cada 10 s, ou pong de protocolo) e partidas ativas.
// Presença != disponibilidade: convites/filas continuam com as próprias validações.
//
// Por socket (interno): ativo -> suspeito (silêncio >= SUSPECT: servidor manda ping de protocolo)
//                       -> morto (silêncio >= DEAD: servidor encerra o socket; fora de partida).
// Por conta: sem sessão utilizável -> tolerância (GRACE) -> offline. Reconectar dentro da tolerância
// não publica nada (sem "piscar" offline/online para os amigos).
// Estado em memória, uma instância. A interface (sessionsOf/stateOf/publish) foi mantida pequena para
// poder trocar por um armazenamento compartilhado (ex.: Redis + pub/sub) no futuro.
const crypto = require('crypto');
const { UUID_RE } = require('../accounts/store');

const env = (k, d) => Number(process.env[k] || d); // env só para testes
const CFG = {
  suspectMs: env('FRAIHA_PRESENCE_SUSPECT_MS', 30000),
  deadMs: env('FRAIHA_PRESENCE_DEAD_MS', 45000),
  graceMs: env('FRAIHA_PRESENCE_GRACE_MS', 8000),
  tickMs: env('FRAIHA_PRESENCE_TICK_MS', 1000),
};

class Presence {
  constructor({ send, backend, now = () => Date.now(), cfg = CFG }) {
    this.send = send; this.backend = backend; this.now = now; this.cfg = cfg;
    this.epoch = crypto.randomBytes(6).toString('hex'); // muda a cada início do servidor (revisões recomeçam)
    this.pub = new Map();        // uid -> { state, rev } publicado
    this.lostAt = new Map();     // uid -> quando a última sessão utilizável sumiu (início da tolerância)
    this.timer = setInterval(() => this.tick(), cfg.tickMs); this.timer.unref && this.timer.unref();
  }
  // ---------- Sessões ----------
  touch(ws) { ws.lastSeen = this.now(); ws.suspect = false; }
  usable(ws) { return ws.readyState === 1 && !ws.dead; }
  sessionsOf(uid) { return [...(this.backend.online.get(uid) || [])].filter(ws => this.usable(ws)); }
  // Estado "bruto" agora (sem tolerância).
  raw(uid) {
    if (!this.sessionsOf(uid).length) return 'offline';
    return this.backend.inMatch(uid) ? 'in_match' : 'online';
  }
  stateOf(uid) { const p = this.pub.get(uid); return p ? p.state : 'offline'; }
  revOf(uid) { const p = this.pub.get(uid); return p ? p.rev : 0; }
  entry(uid) { return { user_id: uid, state: this.stateOf(uid), rev: this.revOf(uid) }; }

  // Chamado pelo backend quando sessões/partidas mudam (primeiro/último socket, início/fim de partida).
  changed(uid) { this.evaluate(uid); }
  evaluate(uid, now = this.now()) {
    if (!UUID_RE.test(String(uid))) return;   // convidados não têm amigos: nada a publicar
    const raw = this.raw(uid), cur = this.stateOf(uid);
    if (raw === 'offline') {
      if (cur === 'offline') { this.lostAt.delete(uid); return; }
      if (!this.lostAt.has(uid)) this.lostAt.set(uid, now);          // começa a tolerância
      if (now - this.lostAt.get(uid) < this.cfg.graceMs) return;     // ainda dentro dela: mantém
      this.lostAt.delete(uid);
      return this.publish(uid, 'offline');
    }
    this.lostAt.delete(uid);                                         // voltou: cancela a tolerância
    if (raw !== cur) this.publish(uid, raw);
  }
  publish(uid, state) {
    const rev = this.revOf(uid) + 1;
    this.pub.set(uid, { state, rev });
    this.notifyFriends(uid).catch(e => console.error('presence notify', e && e.message));
  }
  // Autorização conferida na hora de emitir: só amigos atuais, sem bloqueio em nenhum sentido.
  async audience(uid) {
    const rel = await this.backend.store.getRelations(uid);
    return rel.friends.filter(f => !rel.blocked.includes(f) && !rel.blockedBy.includes(f));
  }
  async notifyFriends(uid) {
    const friends = await this.audience(uid);
    const msg = { type: 'presence_update', epoch: this.epoch, ...this.entry(uid) }; // estado atual (não o de antes do await)
    for (const f of friends) for (const ws of this.sessionsOf(f)) this.send(ws, msg);
  }
  // Após login/reconexão: presença atual dos amigos autorizados.
  async snapshot(ws) {
    const uid = ws.user && ws.user.id; if (!uid) return;
    const friends = await this.audience(uid);
    this.send(ws, { type: 'presence_snapshot', epoch: this.epoch, friends: friends.map(f => this.entry(f)) });
  }

  // ---------- Checagem central (1 s) ----------
  tick() {
    const now = this.now();
    for (const [uid, set] of this.backend.online) {
      for (const ws of set) {
        if (ws.readyState !== 1 || ws.lastSeen === undefined) continue;
        const quiet = now - ws.lastSeen;
        // Em partida, o socket não é encerrado por silêncio: a reconexão/abandono da partida seguem como antes.
        if (quiet >= this.cfg.deadMs && !this.backend.inMatch(uid)) {
          ws.dead = true;
          try { ws.terminate ? ws.terminate() : ws.close(); } catch (_) { /* já fechado */ }
          continue;
        }
        if (quiet >= this.cfg.suspectMs && !ws.suspect) {
          ws.suspect = true;
          try { ws.ping && ws.ping(); } catch (_) { /* ignore */ }   // navegador/cliente responde pong sozinho se vivo
        }
      }
    }
    for (const uid of new Set([...this.backend.online.keys(), ...this.lostAt.keys(), ...[...this.pub.keys()].filter(u => this.stateOf(u) !== 'offline')])) this.evaluate(uid, now);
  }
  stop() { clearInterval(this.timer); }
}
module.exports = { Presence, CFG };
