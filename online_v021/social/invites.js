'use strict';
const { look: publicLook } = require('../accounts/cosmetics');
// Convites para partida Casual entre AMIGOS. Camada separada: só valida, reserva os dois
// jogadores e chama o startMatch() do Casual existente (sem PL, sem código de sala).
// Em memória (V1): convites somem se o servidor reiniciar; o cliente recebe invite_snapshot vazio.
//
// Estados: pending -> starting -> accepted            (partida criada; match_id)
//          pending -> declined | cancelled | expired  (fechados)
//          starting -> failed                         (revalidação falhou; reservas liberadas)
// Regra V1: no máximo UM convite pendente envolvendo cada jogador (como remetente ou destinatário).
const crypto = require('crypto');
const { CASUAL_MODES } = require('../ranked/config');
const { UUID_RE } = require('../accounts/store');
const { operation } = require('../accounts/operation');
const { GAMES } = require('../modes/party');   // R35: convite também para MARCHA REAL e XEQUE (mesa online + bots)

const TTL_MS = Number(process.env.FRAIHA_TEST_INVITE_TTL_MS || 60000); // env só para testes
const OPEN = new Set(['pending', 'starting']);

class Invites {
  constructor({ send, backend, now = () => Date.now() }) {
    this.send = send; this.backend = backend; this.now = now;
    this.invites = new Map();   // id -> convite
    this.byUser = new Map();    // uid -> id do convite aberto (pending/starting)
    this.rate = new Map();
    this.timer = setInterval(() => this.tick(), 1000); this.timer.unref && this.timer.unref();
  }
  store() { return this.backend.store; }
  casual() { return this.backend.casual; }
  sockets(uid) { return this.backend.socketsOf ? this.backend.socketsOf(uid) : []; }
  toUser(uid, msg) { for (const ws of this.sockets(uid)) this.send(ws, msg); }
  fail(ws, message, code, extra = {}) { this.send(ws, { type: 'invite_error', message, code, ...extra }); }
  openOf(uid) { const inv = this.invites.get(this.byUser.get(uid)); return inv && OPEN.has(inv.status) ? inv : null; }
  // Reservado = convite sendo aceito (partida prestes a ser criada): não entra em fila nem em outra partida.
  reserved(uid) { const inv = this.openOf(uid); return !!inv && inv.status === 'starting'; }
  inQueue(uid) { return this.backend.games().some(g => g.mm.has(uid)); }
  view(inv, now = this.now()) {
    const game = inv.game || 'chess';
    return { id: inv.id, from: inv.from, to: inv.to, mode: inv.mode, game, mode_name: game === 'chess' ? CASUAL_MODES[inv.mode].name : GAMES[game].name, minutes: game === 'chess' ? CASUAL_MODES[inv.mode].minutes : 0,
      created_at: new Date(inv.created).toISOString(), expires_at: new Date(inv.expires).toISOString(),
      expires_in_ms: Math.max(0, inv.expires - now), status: inv.status, reason: inv.reason || '', match_id: inv.match_id || '' };
  }
  // Cada lado recebe o convite com o seu papel (sender/recipient).
  emit(inv, type, extra = {}, now = this.now()) {
    const v = { ...this.view(inv, now), ...extra };
    this.toUser(inv.from.user_id, { type, invite: { ...v, role: 'sender' } });
    this.toUser(inv.to.user_id, { type, invite: { ...v, role: 'recipient' } });
  }
  broadcast(inv) { this.emit(inv, 'invite_updated'); }
  viewFor(inv, uid) { return { ...this.view(inv), role: inv.from.user_id === uid ? 'sender' : 'recipient' }; }
  close(inv, status, reason = '', message = '') {
    if (!OPEN.has(inv.status)) return false;
    inv.status = status; inv.reason = reason; inv.message = message;
    for (const u of [inv.from.user_id, inv.to.user_id]) if (this.byUser.get(u) === inv.id) this.byUser.delete(u);
    this.emit(inv, 'invite_updated', message ? { message } : {});
    setTimeout(() => this.invites.delete(inv.id), 120000).unref();
    return true;
  }
  tick() {
    const now = this.now();
    for (const inv of this.invites.values()) if (inv.status === 'pending' && now >= inv.expires) this.close(inv, 'expired', 'expired', 'O convite expirou.');
  }
  limited(uid) {
    const now = this.now(), t = (this.rate.get(uid) || []).filter(x => now - x < 10000);
    t.push(now); this.rate.set(uid, t);
    return t.length > 20;
  }
  // Ocupado para convite: partida ativa, fila (Casual/Ranked) ou outro convite aberto.
  busyReason(uid, self) {
    if (this.backend.inMatch(uid)) return self ? ['in_match', 'Você já está em uma partida.'] : ['target_in_match', 'Este amigo está em uma partida agora.'];
    if (this.inQueue(uid)) return self ? ['in_queue', 'Saia da fila para convidar.'] : ['target_in_queue', 'Este amigo está procurando partida agora.'];
    return null;
  }
  static relationProblem(rel, other) {
    if (rel.blocked.includes(other)) return ['blocked', 'Você bloqueou este jogador.'];
    if (rel.blockedBy.includes(other)) return ['unavailable', 'Não é possível convidar este jogador.'];
    if (!rel.friends.includes(other)) return ['not_friends', 'Só é possível convidar amigos.'];
    return null;
  }

  // ---------- Ganchos chamados pelo backend ----------
  onAuthenticated(ws) {
    const uid = ws.user && ws.user.id; if (!uid) return;
    const inv = this.openOf(uid);
    this.send(ws, { type: 'invite_snapshot', invites: inv ? [this.viewFor(inv, uid)] : [] });
  }
  // Jogador entrou em fila (Casual ou Ranked): o convite aberto dele é cancelado (a ação dele prevalece).
  onQueue(uid) {
    const inv = this.openOf(uid);
    if (inv && inv.status === 'pending') this.close(inv, 'cancelled', 'queue', 'Convite cancelado: um dos jogadores entrou na fila.');
  }
  // Amizade removida ou bloqueio: convite entre os dois é cancelado na hora.
  onRelationChanged(a, b) {
    const inv = this.openOf(a);
    if (inv && inv.status === 'pending' && [inv.from.user_id, inv.to.user_id].includes(b)) this.close(inv, 'cancelled', 'relation', 'Convite cancelado.');
  }

  async handle(ws, m) {
    const op = operation(this.backend, ws);
    const a = String(m.type || ''), me = op.uid, now = this.now();
    if (this.limited(me)) return this.fail(ws, 'Muitas ações seguidas. Aguarde alguns segundos.', 'rate_limited');
    if (a === 'invite_sync') return this.onAuthenticated(ws);
    if (a === 'invite_send') {
      const other = String(m.user_id || ''), game = String(m.game || 'chess');
      const mode = game === 'chess' ? String(m.mode || '') : game;
      if (!UUID_RE.test(other)) return this.fail(ws, 'Jogador inválido.', 'bad_user');
      if (other === me) return this.fail(ws, 'Você não pode convidar a si mesmo.', 'self');
      if (game !== 'chess' && !GAMES[game]) return this.fail(ws, 'Modo inválido.', 'bad_mode');
      if (game === 'chess' && !CASUAL_MODES[mode]) return this.fail(ws, 'Tempo inválido. Escolha 3, 5, 10 ou 20 minutos.', 'bad_mode');
      if (this.backend.modeOpen && !this.backend.modeOpen(game === 'chess' ? 'casual' : game)) return this.fail(ws, require('../admin/controls').CLOSED_MESSAGE, 'mode_disabled');   // FRAIHA Admin
      const mine = this.openOf(me);
      if (mine) {
        // Reenvio do mesmo convite (clique duplo / pacote repetido): devolve o existente.
        if (mine.from.user_id === me && mine.to.user_id === other && mine.mode === mode && (mine.game || 'chess') === game && mine.status === 'pending') return this.send(ws, { type: 'invite_sent', invite: this.viewFor(mine, me), duplicate: true });
        return this.fail(ws, mine.from.user_id === me ? 'Você já tem um convite enviado. Cancele-o para enviar outro.' : 'Você tem um convite pendente. Aceite ou recuse primeiro.', 'pending_exists', { invite: this.viewFor(mine, me) });
      }
      const [peer] = await op.wait(() => this.store().getProfilesByIds([other]));
      if (!peer) return this.fail(ws, 'Jogador não encontrado.', 'not_found');
      const rel = await op.wait(() => this.store().getRelations(me));
      op.assert();
      const rp = Invites.relationProblem(rel, other);
      if (rp) return this.fail(ws, rp[1], rp[0]);
      const b1 = this.busyReason(me, true); if (b1) return this.fail(ws, b1[1], b1[0]);
      if (!this.sockets(other).length) return this.fail(ws, 'Este amigo está offline.', 'target_offline');
      const b2 = this.busyReason(other, false); if (b2) return this.fail(ws, b2[1], b2[0]);
      // FRAIHA Admin (auditoria): o modo pode ter sido desativado durante as consultas acima → revalida antes de criar.
      if (this.backend.modeOpen && !this.backend.modeOpen(game === 'chess' ? 'casual' : game)) return this.fail(ws, require('../admin/controls').CLOSED_MESSAGE, 'mode_disabled');
      // Revalida depois do await: nada de dois convites abertos para ninguém.
      if (this.openOf(me)) return this.fail(ws, 'Você já tem um convite pendente.', 'pending_exists', { invite: this.view(this.openOf(me)) });
      if (this.openOf(other)) return this.fail(ws, 'Este amigo já tem um convite pendente.', 'target_busy');
      const p = op.profile;
      const inv = { id: crypto.randomUUID(), from: { user_id: me, nickname: p.nickname, avatar_id: (op.identity && op.identity.avatar) || p.avatar_id, ...publicLook(op.identity) }, to: { user_id: other, nickname: peer.nickname, avatar_id: peer.avatar_id, ...publicLook(peer) },
        mode, game, created: now, expires: now + TTL_MS, status: 'pending' };
      this.invites.set(inv.id, inv); this.byUser.set(me, inv.id); this.byUser.set(other, inv.id);
      this.toUser(me, { type: 'invite_sent', invite: { ...this.view(inv, now), role: 'sender' } });
      this.toUser(other, { type: 'invite_received', invite: { ...this.view(inv, now), role: 'recipient' } });
      return;
    }
    const inv = this.invites.get(String(m.invite_id || ''));
    if (!inv || (inv.from.user_id !== me && inv.to.user_id !== me)) return this.fail(ws, 'Convite não encontrado.', 'not_found', { invite_id: String(m.invite_id || '') });
    if (a === 'invite_cancel') {
      if (inv.from.user_id !== me) return this.fail(ws, 'Só quem enviou pode cancelar.', 'not_sender', { invite: this.view(inv) });
      if (inv.status !== 'pending') return this.send(ws, { type: 'invite_updated', invite: this.viewFor(inv, me) });
      this.close(inv, 'cancelled', 'sender', 'Convite cancelado por quem enviou.');
      return;
    }
    if (a === 'invite_decline') {
      if (inv.to.user_id !== me) return this.fail(ws, 'Este convite não é para você.', 'not_recipient', { invite: this.view(inv) });
      if (inv.status !== 'pending') return this.send(ws, { type: 'invite_updated', invite: this.viewFor(inv, me) });
      this.close(inv, 'declined', 'recipient', `${inv.to.nickname} recusou o convite.`);
      return;
    }
    if (a === 'invite_accept') return this.accept(ws, inv, me);
    return this.fail(ws, 'Ação de convite desconhecida.', 'invalid');
  }

  async accept(ws, inv, me) {
    const op = operation(this.backend, ws);
    if (inv.to.user_id !== me) return this.fail(ws, 'Este convite não é para você.', 'not_recipient', { invite: this.view(inv) });
    // Idempotente: aceite repetido (clique duplo / pacote repetido) só devolve o estado atual.
    if (inv.status !== 'pending') return this.send(ws, { type: 'invite_updated', invite: this.viewFor(inv, me) });
    if (this.now() >= inv.expires) { this.close(inv, 'expired', 'expired', 'O convite expirou.'); return; }
    // Reserva os dois ANTES de qualquer await: fila, outro convite e segundo aceite ficam bloqueados.
    inv.status = 'starting';
    this.broadcast(inv);
    const from = inv.from.user_id, to = inv.to.user_id;
    const release = (code, message) => { inv.status = 'pending'; this.close(inv, 'failed', code, message); };
    const participants = [from, to].map(uid => uid === me ? ws : this.sockets(uid).at(-1));
    const guards = participants.map(socket => socket && operation(this.backend, socket));
    try {
      const rel = await op.wait(() => this.store().getRelations(to));
      for (const guard of guards) {
        if (!guard) return release('offline', 'Um dos jogadores está offline.');
        await guard.wait(() => Promise.resolve());
      }
      op.assert();
      for (const guard of guards) guard.assert();
      if (inv.status !== 'starting' || this.byUser.get(from) !== inv.id || this.byUser.get(to) !== inv.id) return;
      const rp = Invites.relationProblem(rel, from);
      if (rp) return release(rp[0], rp[0] === 'not_friends' ? 'Convite cancelado: vocês não são mais amigos.' : 'Convite cancelado.');
    } catch (e) {
      if (this.backend.cancelled && this.backend.cancelled(e)) {
        return this.backend.operations.run(null, () => release('session_changed', 'Convite cancelado: sessão alterada ou indisponível.'));
      }
      console.error('invite accept', e && e.message);
      return release('server_error', 'Erro temporário no servidor. Tente novamente.');
    }
    // FRAIHA Admin: modo desativado depois do convite → não começa (partidas em andamento não são tocadas).
    if (this.backend.modeOpen && !this.backend.modeOpen((inv.game || 'chess') === 'chess' ? 'casual' : inv.game)) return release('mode_disabled', require('../admin/controls').CLOSED_MESSAGE);
    // Partida ativa sempre tem prioridade. Tudo daqui até o startMatch é síncrono (sem corrida).
    for (const [uid, who] of [[from, inv.from.nickname], [to, inv.to.nickname]]) {
      if (this.backend.inMatch(uid)) return release('busy', `${who} já está em uma partida.`);
      if (this.inQueue(uid)) return release('busy', `${who} está em uma fila.`);
      if (!this.sockets(uid).length) return release('offline', `${who} está offline.`);
    }
    if ((inv.game || 'chess') !== 'chess') {
      // R35 · MARCHA REAL / XEQUE: mesa de 4 no servidor (quem convidou + amigo + 2 bots)
      const party = this.backend.party;
      if (!party) return release('server_error', 'Modo indisponível no servidor.');
      let room;
      try { room = party.start(inv.game, [inv.from, inv.to]); }
      catch (e) { console.error('invite party start', e && e.message); return release('server_error', 'Não foi possível iniciar a partida.'); }
      inv.status = 'accepted'; inv.match_id = room.id;
      for (const u of [from, to]) if (this.byUser.get(u) === inv.id) this.byUser.delete(u);
      this.broadcast(inv);
      for (const u of [from, to]) if (this.backend.presenceChanged) this.backend.presenceChanged(u);
      setTimeout(() => this.invites.delete(inv.id), 120000).unref();
      return;
    }
    const casual = this.casual();
    if (!casual) return release('server_error', 'Casual indisponível no servidor.');
    const entry = (u, since) => {
      casual.sockets.set(u.user_id, participants[u.user_id === from ? 0 : 1]);
      return { userId: u.user_id, nickname: u.nickname, avatar: u.avatar_id, ...publicLook(u), stats: null, since };
    };
    let match;
    try { match = casual.startMatch(inv.mode, entry(inv.from, inv.created), entry(inv.to, inv.created + 1)); }
    catch (e) { console.error('invite startMatch', e && e.message); return release('server_error', 'Não foi possível iniciar a partida.'); }
    inv.status = 'accepted'; inv.match_id = match.id;
    for (const u of [from, to]) if (this.byUser.get(u) === inv.id) this.byUser.delete(u);
    this.broadcast(inv);
    setTimeout(() => this.invites.delete(inv.id), 120000).unref();
  }
  stop() { clearInterval(this.timer); }
}
module.exports = { Invites, TTL_MS };
