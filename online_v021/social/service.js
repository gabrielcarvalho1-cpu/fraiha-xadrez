'use strict';
// Amigos: busca por nickname, perfil público, pedidos, amizades e bloqueios.
// Só contas com perfil. O servidor decide tudo; o cliente só pede. Nunca expõe e-mail.
const { MODES } = require('../ranked/config');
const { UUID_RE, STAT_MODES } = require('../accounts/store');
const { operation } = require('../accounts/operation');
const NICK_QUERY = /^[A-Za-z0-9_.À-ÖØ-öø-ÿ-]{2,16}$/;

class Social {
  constructor({ send, backend, now = () => Date.now() }) {
    this.send = send; this.backend = backend; this.now = now;
    this.rate = new Map(); // uid -> timestamps
  }
  store() { return this.backend.store; }
  fail(ws, message, code = '') { this.send(ws, { type: 'social_error', message, code }); }
  limited(uid, max = 20, windowMs = 10000) {
    const now = this.now(), t = (this.rate.get(uid) || []).filter(x => now - x < windowMs);
    t.push(now); this.rate.set(uid, t);
    return t.length > max;
  }
  presenceOf(uid) { return this.backend.presenceOf ? this.backend.presenceOf(uid) : 'offline'; }
  static relation(rel, other) {
    if (rel.blocked.includes(other)) return 'blocked';
    if (rel.friends.includes(other)) return 'friend';
    if (rel.sent.includes(other)) return 'request_sent';
    if (rel.received.includes(other)) return 'request_received';
    return 'none';
  }
  async list(uid) {
    const op = operation(this.backend);
    const rel = await op.wait(() => this.store().getRelations(uid));
    const ids = [...new Set([...rel.friends, ...rel.sent, ...rel.received, ...rel.blocked])];
    const byId = new Map((await op.wait(() => this.store().getProfilesByIds(ids))).map(p => [p.user_id, p]));
    const pick = arr => arr.map(id => byId.get(id)).filter(Boolean);
    const unread = this.backend.dm ? await op.wait(() => this.backend.dm.unreadCounts(uid).catch(() => ({}))) : {};
    return { type: 'social_list',
      friends: pick(rel.friends).map(p => ({ ...p, presence: this.presenceOf(p.user_id), presence_rev: this.backend.presenceRevOf ? this.backend.presenceRevOf(p.user_id) : 0, unread: unread[p.user_id] || 0 })),
      presence_epoch: this.backend.presence ? this.backend.presence.epoch : '',
      received: pick(rel.received), sent: pick(rel.sent), blocked: pick(rel.blocked) };
  }
  async pushList(uid) {
    const op = operation(this.backend);
    const socks = this.backend.socketsOf ? this.backend.socketsOf(uid) : [];
    if (!socks.length) return;
    const l = await op.wait(() => this.list(uid));
    op.assert();
    for (const ws of (this.backend.socketsOf ? this.backend.socketsOf(uid) : [])) this.send(ws, l);
  }
  notify(uid, event, user) {
    for (const ws of (this.backend.socketsOf ? this.backend.socketsOf(uid) : [])) this.send(ws, { type: 'social_event', event, user });
  }
  // R37 · cartão de perfil (passar o mouse no avatar durante a partida): perfil público, relação
  // (para o botão ADICIONAR AMIGO) e o placar do MODO em jogo. Vale também para a própria conta.
  async card(ws, me, other, mode) {
    const op = operation(this.backend, ws);
    const st = this.store();
    const rel = await op.wait(() => st.getRelations(me));
    if (other !== me && rel.blockedBy.includes(other)) return this.send(ws, { type: 'social_card', user_id: other, missing: true });
    const [target] = await op.wait(() => st.getProfilesByIds([other]));
    if (!target) return this.send(ws, { type: 'social_card', user_id: other, missing: true });
    let stats = null;
    if (MODES[mode]) {
      const s = (await op.wait(() => st.getRankedStats(other)))[mode] || {};
      stats = { wins: s.wins || 0, losses: s.losses || 0, draws: s.draws || 0, league: s.league || 0, pl: s.pl || 0 };
    } else if (STAT_MODES.includes(mode)) {
      const all = st.getModeStats ? await op.wait(() => st.getModeStats(other)) : { not_configured: true };
      stats = all.not_configured ? null : all[mode];
    }
    this.send(ws, { type: 'social_card', user_id: other, mode, card: { ...target, relation: other === me ? 'self' : Social.relation(rel, other), stats, stats_ready: stats !== null } });
  }
  async handle(ws, m) {
    const op = operation(this.backend, ws);
    const a = String(m.type || ''), me = op.uid, meProfile = op.profile;
    if (this.limited(me)) return this.fail(ws, 'Muitas ações seguidas. Aguarde alguns segundos.', 'rate_limited');
    const st = this.store();
    if (a === 'social_list') return this.send(ws, await op.wait(() => this.list(me)));
    if (a === 'social_search') {
      const q = String(m.query || '').trim();
      if (!NICK_QUERY.test(q)) return this.fail(ws, 'Digite ao menos 2 caracteres do nickname (letras, números, . _ -).', 'bad_query');
      const rel = await op.wait(() => st.getRelations(me));
      const found = (await op.wait(() => st.searchProfiles(q, 25))).filter(p => p.user_id !== me && !rel.blockedBy.includes(p.user_id)).slice(0, 20);
      return this.send(ws, { type: 'social_search', query: q, results: found.map(p => ({ ...p, relation: Social.relation(rel, p.user_id) })) });
    }
    const other = String(m.user_id || '');
    if (!UUID_RE.test(other)) return this.fail(ws, 'Jogador inválido.', 'bad_user');
    if (a === 'social_card') return this.card(ws, me, other, String(m.mode || ''));
    if (other === me) return this.fail(ws, 'Esta é a sua própria conta.', 'self');
    const rel = await op.wait(() => st.getRelations(me));
    // Quem me bloqueou não aparece para mim: tratado como inexistente.
    if (rel.blockedBy.includes(other)) return this.fail(ws, 'Jogador não encontrado.', 'not_found');
    const [target] = await op.wait(() => st.getProfilesByIds([other]));
    if (!target) return this.fail(ws, 'Jogador não encontrado.', 'not_found');
    const relation = Social.relation(rel, other);
    if (a === 'social_profile') {
      const stats = await op.wait(() => st.getRankedStats(other));
      const ranked = {}; let highest = 0;
      for (const mode of Object.keys(MODES)) {
        const s = stats[mode] || {};
        ranked[mode] = { league: s.league || 0, pl: s.pl || 0, wins: s.wins || 0, losses: s.losses || 0, draws: s.draws || 0, matches: s.matches || 0, highest_league: s.highest_league || 0 };
        highest = Math.max(highest, ranked[mode].highest_league);
      }
      return this.send(ws, { type: 'social_profile', profile: { ...target, highest_league: highest, ranked,
        presence: relation === 'friend' ? this.presenceOf(other) : '', relation } });   // presença só para amigos
    }
    const done = async (action, notifyEvent) => {
      const newRel = Social.relation(await op.wait(() => st.getRelations(me)), other);
      this.send(ws, { type: 'social_ok', action, user_id: other, relation: newRel });
      await op.wait(() => this.pushList(me));
      op.assert();
      if (notifyEvent) this.notify(other, notifyEvent, { user_id: me, nickname: meProfile.nickname, avatar_id: meProfile.avatar_id });
      await op.wait(() => this.pushList(other));
    };
    if (a === 'social_request') {
      if (relation === 'blocked') return this.fail(ws, 'Você bloqueou este jogador. Desbloqueie para adicionar.', 'blocked');
      if (relation === 'friend') return this.fail(ws, 'Vocês já são amigos.', 'already_friends');
      if (relation === 'request_sent') return this.fail(ws, 'Pedido já enviado. Aguarde a resposta.', 'already_sent');
      if (relation === 'request_received') return this.send(ws, { type: 'social_error', code: 'reverse_pending', user_id: other, relation,
        message: `${target.nickname} já te enviou um pedido de amizade. Aceite o pedido existente.` });
      await op.wait(() => st.addRequest(me, other));
      return done('request', 'request_received');
    }
    if (a === 'social_accept') {
      if (relation !== 'request_received') return this.fail(ws, 'Não há pedido deste jogador.', 'no_request');
      await op.wait(() => st.removeRequest(other, me)); await op.wait(() => st.removeRequest(me, other)); await op.wait(() => st.addFriendship(me, other));
      return done('accept', 'request_accepted');
    }
    if (a === 'social_decline') {
      if (relation !== 'request_received') return this.fail(ws, 'Não há pedido deste jogador.', 'no_request');
      await op.wait(() => st.removeRequest(other, me));
      return done('decline', null);
    }
    if (a === 'social_cancel') {
      if (relation !== 'request_sent') return this.fail(ws, 'Não há pedido enviado para este jogador.', 'no_request');
      await op.wait(() => st.removeRequest(me, other));
      return done('cancel', null);
    }
    if (a === 'social_remove') {
      if (relation !== 'friend') return this.fail(ws, 'Vocês não são amigos.', 'not_friends');
      await op.wait(() => st.removeFriendship(me, other));
      op.assert();
      if (this.backend.onUnfriended) this.backend.onUnfriended(me, other);
      return done('remove', null);
    }
    if (a === 'social_block') {
      await op.wait(() => st.addBlock(me, other));
      await op.wait(() => st.removeFriendship(me, other)); await op.wait(() => st.removeRequest(me, other)); await op.wait(() => st.removeRequest(other, me));
      op.assert();
      if (this.backend.onBlocked) this.backend.onBlocked(me, other);
      return done('block', null);
    }
    if (a === 'social_unblock') {
      if (relation !== 'blocked') return this.fail(ws, 'Este jogador não está bloqueado.', 'not_blocked');
      await op.wait(() => st.removeBlock(me, other));
      return done('unblock', null);
    }
    return this.fail(ws, 'Ação de amigos desconhecida.', 'invalid');
  }
}
module.exports = { Social };
