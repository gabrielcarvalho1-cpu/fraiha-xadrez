'use strict';
// FRAIHA Voice v1 · autorização de voz (servidor). Só ÁUDIO entre HUMANOS em partida online ativa.
// O servidor é quem decide: conta autenticada + sessão válida (garantidas pelo backend antes de
// chegar aqui) + a partida existe, está ativa, é PvP humano e o usuário ainda é participante.
// Só então gera um token Agora curto (TTL), ligado ao canal da partida e ao "assento" do jogador.
// Voz NUNCA é autoridade sobre o jogo: este módulo só lê o estado das partidas, nunca altera.
// Segredos: FRAIHA_AGORA_APP_ID / FRAIHA_AGORA_APP_CERTIFICATE só em variáveis de ambiente;
// nunca em log nem em resposta (só o App ID, que é público por definição da Agora, vai ao cliente).
const { buildRtcAudioToken } = require('./agora_token');

const TOKEN_TTL_S = 600;            // 10 min; o cliente renova antes de expirar (voice_renew)
const RATE_WINDOW_MS = 60e3, RATE_MAX = 12;
const short = id => String(id || '').slice(0, 8);

class VoiceService {
  constructor({ backend, send, env = process.env, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.send = send; this.now = now; this.log = log;
    this.appId = String(env.FRAIHA_AGORA_APP_ID || '').trim();
    this.cert = String(env.FRAIHA_AGORA_APP_CERTIFICATE || '').trim();
    this.ttl = Math.min(3600, Math.max(120, Number(env.FRAIHA_VOICE_TOKEN_TTL || TOKEN_TTL_S) || TOKEN_TTL_S));
    this.rate = new WeakMap();
  }
  configured() { return /^[0-9a-fA-F]{32}$/.test(this.appId) && /^[0-9a-fA-F]{32}$/.test(this.cert); }

  // Onde o usuário está jogando AGORA (só partidas ativas). Bots nunca entram na lista.
  locate(uid, matchId) {
    const b = this.backend;
    for (const g of [b.ranked, b.casual]) {
      if (!g) continue;
      const any = g.matchOf(uid);
      if (!any || any.id !== matchId) continue;
      if (any.status === 'finished') return { error: 'match_over' };
      const color = any.colorOf(uid);
      if (!color) return { error: 'not_in_match' };
      const kind = g.kind === 'casual' ? 'casual' : 'ranked';
      const parts = ['w', 'b'].map((c, i) => ({ uid: i + 1, name: String(any.players[c].nickname || '') }));
      const others = ['w', 'b'].filter(c => c !== color).map(c => any.players[c].userId);
      return { kind, id: any.id, seatUid: color === 'w' ? 1 : 2, participants: parts, others };
    }
    const p = b.party;
    if (p) {
      const room = p.rooms.get(matchId);
      if (room && room.seats.some(s => s.kind === 'human' && s.uid === uid)) {
        if (room.ended) return { error: 'match_over' };
        const seat = p.seatOf(room, uid);
        if (seat < 0 || room.seats[seat].left) return { error: 'not_in_match' };
        const humans = [], others = [];
        room.seats.forEach((s, i) => { if (s.kind === 'human' && !s.left) { humans.push({ uid: i + 1, name: String(s.nickname || '') }); if (i !== seat) others.push(s.uid); } });
        if (humans.length < 2) return { error: 'solo' };
        return { kind: room.game === 'xeque' ? 'xeque' : 'marcha', id: room.id, seatUid: seat + 1, participants: humans, others };
      }
    }
    return { error: 'not_in_match' };
  }

  allow(ws) {
    const t = this.now();
    let r = this.rate.get(ws);
    if (!r || t - r.start > RATE_WINDOW_MS) { r = { start: t, n: 0 }; this.rate.set(ws, r); }
    return ++r.n <= RATE_MAX;
  }

  deny(ws, matchId, code, renew) {
    this.log(`[voice] ${renew ? 'renew' : 'token'} rejected code=${code} match=${short(matchId)}`);
    const msg = {
      not_configured: 'Voz ainda não configurada no servidor.',
      not_in_match: 'Voz só funciona durante a sua partida online.',
      match_over: 'A partida terminou.',
      solo: 'Não há outro jogador humano na mesa.',
      rate_limited: 'Muitas tentativas. Aguarde um pouco.',
      bad_request: 'Pedido de voz inválido.',
      token_error: 'Falha ao gerar acesso de voz.',
    }[code] || 'Voz indisponível.';
    return this.send(ws, { type: 'voice_denied', match_id: String(matchId || ''), code, message: msg, renew: !!renew });
  }

  // Aviso para os OUTROS humanos da mesa: "fulano entrou/saiu da voz" (para quem ainda não entrou
  // saber que pode tocar no microfone). Só nome público + assento; nada de ids de conta ou token.
  notify(where, joined) {
    const me = where.participants.find(p => p.uid === where.seatUid);
    const msg = { type: 'voice_peer', match_id: where.id, uid: where.seatUid, name: me ? me.name : '', joined };
    const b = this.backend;
    for (const other of where.others || []) for (const sock of (b.socketsOf ? b.socketsOf(other) : [])) this.send(sock, msg);
  }

  handle(ws, m) {
    const a = String(m.type || '');
    const uid = ws.user && ws.user.id;
    const matchId = typeof m.match_id === 'string' ? m.match_id.slice(0, 64) : '';
    if (a === 'voice_leave') {   // a saída é do cliente; aqui só registra e avisa a mesa (sem estado no servidor)
      this.log(`[voice] leave match=${short(matchId)} reason=${String(m.reason || '').replace(/[^a-z_]/g, '').slice(0, 24)}`);
      const w = uid && matchId ? this.locate(uid, matchId) : { error: 'x' };
      if (!w.error) this.notify(w, false);
      return;
    }
    if (a !== 'voice_join' && a !== 'voice_renew') return this.deny(ws, matchId, 'bad_request', false);
    const renew = a === 'voice_renew';
    if (!uid) return this.deny(ws, matchId, 'not_in_match', renew);
    if (!/^[A-Za-z0-9-]{8,64}$/.test(matchId)) return this.deny(ws, matchId, 'bad_request', renew);
    if (!this.allow(ws)) return this.deny(ws, matchId, 'rate_limited', renew);
    if (!this.configured()) return this.deny(ws, matchId, 'not_configured', renew);
    const where = this.locate(uid, matchId);
    if (where.error) return this.deny(ws, matchId, where.error, renew);
    const channel = `fx_${where.kind}_${where.id}`;
    let token;
    try { token = buildRtcAudioToken({ appId: this.appId, appCertificate: this.cert, channel, uid: where.seatUid, ttl: this.ttl, privilegeTtl: this.ttl, issueTs: Math.floor(this.now() / 1000) }); }
    catch (e) { console.error('[voice] token build failed', e && e.message); return this.deny(ws, matchId, 'token_error', renew); }
    this.log(`[voice] ${renew ? 'renew' : 'token'} granted kind=${where.kind} match=${short(where.id)} seat=${where.seatUid} ttl=${this.ttl}`);
    if (!renew) this.notify(where, true);
    return this.send(ws, { type: 'voice_granted', renew, match_id: where.id, kind: where.kind, app_id: this.appId, channel,
      uid: where.seatUid, token, ttl: this.ttl, participants: where.participants });
  }
}

module.exports = { VoiceService, TOKEN_TTL_S };
