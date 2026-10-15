'use strict';
// R105 · CONVITE POR LINK e RECOMPENSA POR INDICAÇÃO. O servidor é a autoridade.
// Link: https://jogar.fraihaxadrez.com/?convite=CODIGO (código curto e único por conta, criado na primeira vez).
// Uma conta NOVA criada a partir do link fica ligada a quem convidou (tabela referrals, 0014). Regras:
//   • a conta nova termina 5 partidas online contra outra pessoa → os dois ganham 7 dias de Club
//     (quem convida: até 10 indicações premiadas por mês; depois disso a indicação conta, mas sem prêmio);
//   • a conta nova faz a primeira compra → quem convidou ganha +30 dias de Club.
// Sem a 0014 o link continua levando gente para o jogo; só a indicação não é registrada (fail-soft, com log).
const crypto = require('crypto');

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   // sem 0/O/1/I para não confundir
const CODE_LEN = 7;
const CODE_RE = /^[A-HJ-NP-Z2-9]{7}$/;
const QUALIFY_GAMES = 5, FRIEND_DAYS = 7, PURCHASE_DAYS = 30, MONTH_CAP = 10;
const NOT_REFERRED_TTL = 60 * 60 * 1000;   // conta sem indicação: não pergunta ao banco de novo por 1 h

const missing = e => /42P01|42703|PGRST200|PGRST204|PGRST205|PGRST202|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const newCode = () => { const b = crypto.randomBytes(CODE_LEN); let s = ''; for (let i = 0; i < CODE_LEN; i++) s += ALPHABET[b[i] % ALPHABET.length]; return s; };
const cleanCode = c => { const s = String(c || '').trim().toUpperCase(); return CODE_RE.test(s) ? s : ''; };

class Referrals {
  constructor({ backend, send, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.send = send; this.now = now; this.log = log;
    this.notReferred = new Map();   // uid -> até quando não consultar
    this.busy = new Map();
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.createReferral); }

  async ensureCode(uid) {
    let code = await this.store.getRefCode(uid);
    for (let i = 0; !code && i < 6; i++) { const c = newCode(); if (await this.store.setRefCode(uid, c)) code = c; else code = await this.store.getRefCode(uid); }
    return code;
  }
  monthStart() { const d = new Date(this.now()); d.setUTCDate(1); d.setUTCHours(3, 0, 0, 0); if (d.getTime() > this.now()) d.setUTCMonth(d.getUTCMonth() - 1); return d.toISOString(); }

  // ref_get → ref_info { code, invited, playing, qualified, rewarded_month, cap, rules }
  async handle(ws, m) {
    const uid = ws.user && ws.user.id;
    if (!uid || !ws.profile) return this.send(ws, { type: 'ref_info', available: false, message: 'Entre na sua conta para convidar amigos.' });
    if (String(m.type) !== 'ref_get') return;
    const rules = { games: QUALIFY_GAMES, friend_days: FRIEND_DAYS, purchase_days: PURCHASE_DAYS, cap: MONTH_CAP };
    if (!this.ok()) return this.send(ws, { type: 'ref_info', available: false, rules });
    try {
      const code = await this.ensureCode(uid);
      const rows = await this.store.listReferralsBy(uid);
      const ms = this.monthStart();
      this.send(ws, { type: 'ref_info', available: true, code, rules,
        invited: rows.length, playing: rows.filter(r => !r.qualified_at).length, qualified: rows.filter(r => r.qualified_at).length,
        rewarded_month: rows.filter(r => r.rewarded_at && r.rewarded_at >= ms).length,
        purchases: rows.filter(r => r.purchase_rewarded_at).length });
    } catch (e) {
      if (!missing(e)) console.error('[indicacao] ref_get', e && e.message);
      // sem a 0014: o link funciona com o código "vazio" (só traz a pessoa, sem registrar)
      this.send(ws, { type: 'ref_info', available: false, rules });
    }
  }

  // Conta NOVA criada (acct_create_profile) com um código de convite.
  async onProfileCreated(uid, rawCode) {
    const code = cleanCode(rawCode);
    if (!code || !this.ok()) return null;
    try {
      const who = await this.store.findByRefCode(code);
      if (!who || who.user_id === uid) return null;
      const r = await this.store.createReferral(uid, who.user_id);
      if (r) { this.notReferred.delete(uid); this.log('[indicacao] ' + JSON.stringify({ referrer: who.user_id, referred: uid })); }
      return r;
    } catch (e) { if (!missing(e)) console.error('[indicacao] criar', e && e.message); return null; }
  }

  // Partida online terminada contra outra PESSOA (Casual, Ranqueada, XEQUE/Marcha com amigos).
  async onGame(uid) {
    if (!this.ok() || !uid) return;
    const until = this.notReferred.get(uid);
    if (until && until > this.now()) return;
    if (this.busy.get(uid)) return this.busy.get(uid).then(() => this.onGame(uid));
    const job = this._game(uid).finally(() => this.busy.delete(uid));
    this.busy.set(uid, job);
    return job;
  }
  async _game(uid) {
    try {
      const r = await this.store.getReferral(uid);
      if (!r) { this.notReferred.set(uid, this.now() + NOT_REFERRED_TTL); return; }
      if (r.qualified_at) { this.notReferred.set(uid, this.now() + NOT_REFERRED_TTL); return; }
      const games = (r.games || 0) + 1;
      const patch = { games };
      if (games >= QUALIFY_GAMES) patch.qualified_at = new Date(this.now()).toISOString();
      const upd = await this.store.updateReferral(uid, patch, { games: r.games || 0 });
      if (!upd || !patch.qualified_at) return;
      // prêmio dos dois (limite mensal de quem convida)
      const ms = this.monthStart();
      const month = (await this.store.listReferralsBy(r.referrer_id)).filter(x => x.rewarded_at && x.rewarded_at >= ms).length;
      if (month >= MONTH_CAP) { this.log('[indicacao] limite do mes ' + r.referrer_id); return; }
      const got = await this.store.updateReferral(uid, { rewarded_at: new Date(this.now()).toISOString() }, { rewarded_at: null });
      if (!got) return;
      await this.store.grantClubDays(uid, FRIEND_DAYS, 'referral');
      await this.store.grantClubDays(r.referrer_id, FRIEND_DAYS, 'referral');
      await this.notify(uid, `Você completou ${QUALIFY_GAMES} partidas: ganhou ${FRIEND_DAYS} dias de Club FRAIHA pelo convite!`);
      await this.notify(r.referrer_id, `Um amigo que você convidou completou ${QUALIFY_GAMES} partidas: você ganhou ${FRIEND_DAYS} dias de Club FRAIHA!`);
    } catch (e) { if (!missing(e)) console.error('[indicacao] partida', e && e.message); }
  }

  // Primeira compra da conta convidada → +30 dias de Club para quem convidou (uma vez).
  async onPurchase(uid) {
    if (!this.ok() || !uid) return;
    try {
      const r = await this.store.getReferral(uid);
      if (!r || r.purchase_rewarded_at) return;
      const got = await this.store.updateReferral(uid, { purchase_rewarded_at: new Date(this.now()).toISOString() }, { purchase_rewarded_at: null });
      if (!got) return;
      await this.store.grantClubDays(r.referrer_id, PURCHASE_DAYS, 'referral');
      await this.notify(r.referrer_id, `Um amigo que você convidou apoiou o FRAIHA: você ganhou +${PURCHASE_DAYS} dias de Club FRAIHA!`);
    } catch (e) { if (!missing(e)) console.error('[indicacao] compra', e && e.message); }
  }

  async notify(uid, message) {
    for (const ws of this.backend.socketsOf ? this.backend.socketsOf(uid) : []) {
      this.send(ws, { type: 'ref_reward', message });
      try { await this.backend.state(ws); } catch { /* a próxima leitura corrige */ }
    }
  }
}

module.exports = { Referrals, cleanCode, newCode, CODE_RE, QUALIFY_GAMES, FRIEND_DAYS, PURCHASE_DAYS, MONTH_CAP };
