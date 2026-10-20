'use strict';
// R104 · DENÚNCIAS e SUSPENSÃO. O servidor é a autoridade.
// Denúncia: guardada no banco (tabela reports da 0013) com um trecho do contexto (mensagens recentes de quem foi
// denunciado). Sem a 0013 (ou no store de memória sem tabela) cai no log do servidor — a denúncia nunca se perde
// silenciosamente. Limites: 10 denúncias a cada 10 min por conta; a mesma denúncia (quem, quem, onde) só 1x a cada 30 min.
// Suspensão: profiles.account_status = 'suspended' (+ suspended_until). Conta suspensa não entra; o servidor tira a
// suspensão sozinho quando o prazo passa.
const KINDS = ['match', 'dm', 'profile', 'global_chat'];
const KIND_LABEL = { match: 'Partida (chat e voz)', dm: 'Conversa privada', profile: 'Perfil', global_chat: 'CHAT GLOBAL' };
const RATE_N = 10, RATE_MS = 10 * 60 * 1000, DUP_MS = 30 * 60 * 1000;
const MAX_MSGS = 20, MAX_TEXT = 500, MAX_CONTEXT = 8000;

function cleanContext(ctx) {
  const out = {};
  if (!ctx || typeof ctx !== 'object') return out;
  for (const k of ['reporter_nickname', 'reported_nickname', 'mode', 'voice']) if (ctx[k] !== undefined) out[k] = typeof ctx[k] === 'string' ? ctx[k].slice(0, 80) : ctx[k];
  if (Array.isArray(ctx.messages)) out.messages = ctx.messages.slice(-MAX_MSGS).map(t => String(t && t.text !== undefined ? t.text : t).slice(0, MAX_TEXT));
  let json = JSON.stringify(out);
  while (json.length > MAX_CONTEXT && out.messages && out.messages.length) { out.messages.shift(); json = JSON.stringify(out); }
  return out;
}

const missingTable = e => /42P01|PGRST205|42703|PGRST204|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));

class Reports {
  constructor({ backend, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.now = now; this.log = log;
    this.rate = new Map();   // reporter -> [ts]
    this.recent = new Map(); // chave -> ts
  }
  get store() { return this.backend.store; }
  // Devolve { ok, duplicate?, persisted } ou { error, code }.
  async file({ reporter, reported, kind, ref = '', reason = '', context = {} }) {
    if (!reporter || !reported || reporter === reported) return { error: 'Denúncia inválida.', code: 'invalid' };
    if (!KINDS.includes(kind)) return { error: 'Denúncia inválida.', code: 'invalid' };
    const now = this.now(), key = [reporter, reported, kind, ref].join('|');
    for (const [k, t] of this.recent) if (now - t > DUP_MS) this.recent.delete(k);
    if (this.recent.has(key)) return { ok: true, duplicate: true, persisted: true };
    const times = (this.rate.get(reporter) || []).filter(t => now - t < RATE_MS);
    if (times.length >= RATE_N) return { error: 'Você fez muitas denúncias seguidas. Aguarde alguns minutos.', code: 'rate_limited' };
    if (this.rate.size > 20000) for (const [k, v] of this.rate) if (!v.length || now - v[v.length - 1] > RATE_MS) this.rate.delete(k);   // R171 · SEC-010: mapa com teto
    times.push(now); this.rate.set(reporter, times); this.recent.set(key, now);
    const row = { reporter_id: reporter, reported_id: reported, kind, ref: String(ref || '').slice(0, 80), reason: String(reason || '').slice(0, 200), context: cleanContext(context) };
    this.log('[denuncia] ' + JSON.stringify({ kind, reporter, reported, ref: row.ref, at: new Date(now).toISOString() }));
    if (this.store && this.store.createReport) {
      try { await this.store.createReport(row); return { ok: true, persisted: true }; }
      catch (e) {
        if (!missingTable(e)) {
          // R171b · SEC-010 (reteste Orca): falha de gravação NÃO conta como denúncia feita — desfaz a marca de
          // repetida e o uso do limite, e responde erro para a pessoa tentar de novo.
          console.error('[denuncia] erro ao gravar', e && e.message);
          this.recent.delete(key);
          const list = this.rate.get(reporter) || []; const i = list.lastIndexOf(now); if (i >= 0) list.splice(i, 1);
          return { error: 'Não foi possível registrar a denúncia agora. Tente de novo em instantes.', code: 'report_failed' };
        }
      }
    }
    this.log('[denuncia-sem-tabela] ' + JSON.stringify(row));   // sem a 0013: fica no log do Render
    return { ok: true, persisted: false };
  }

  // ---------------------------------------------------------------- suspensão
  // Perfil suspenso agora? Prazo vencido → volta para 'active' (no banco) e devolve null.
  async activeSuspension(profile) {
    if (!profile || profile.account_status !== 'suspended') return null;
    const until = profile.suspended_until ? Date.parse(profile.suspended_until) : null;
    if (until !== null && Number.isFinite(until) && until <= this.now()) {
      try { await this.store.setSuspension(profile.user_id, false); } catch (e) { console.error('[suspensao] liberar', e && e.message); }
      profile.account_status = 'active';
      return null;
    }
    return { until: profile.suspended_until || null, reason: profile.suspension_reason || '' };
  }
  static message(s) {
    const d = s && s.until ? new Date(s.until) : null;
    const quando = d ? ' até ' + d.toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : ' por tempo indeterminado';
    return 'Sua conta está suspensa' + quando + (s && s.reason ? '. Motivo: ' + s.reason : '') + '. Se acha que foi um engano, fale com a gente pelo contato dos Termos de Uso.';
  }
  // days: número (1–3650) ou null (indeterminado). Desconecta a conta na hora.
  async suspend(uid, days, reason) {
    if (!this.store || !this.store.setSuspension) return { error: 'unavailable' };
    const until = days ? new Date(this.now() + days * 86400000).toISOString() : null;
    let p;
    try { p = await this.store.setSuspension(uid, until, reason); }
    catch (e) { return { error: missingTable(e) ? 'migration_0013_missing' : 'query_error' }; }
    if (!p) return { error: 'not_found' };
    const s = { until, reason: String(reason || '') };
    for (const ws of this.backend.socketsOf ? this.backend.socketsOf(uid) : []) {
      this.backend.send(ws, { type: 'acct_suspended', message: Reports.message(s), until });
      if (this.backend.invalidate) this.backend.invalidate(ws);
    }
    return { ok: true, until };
  }
  async unsuspend(uid) {
    if (!this.store || !this.store.setSuspension) return { error: 'unavailable' };
    try { const p = await this.store.setSuspension(uid, false); return p ? { ok: true } : { error: 'not_found' }; }
    catch (e) { return { error: missingTable(e) ? 'migration_0013_missing' : 'query_error' }; }
  }
}

module.exports = { Reports, KINDS, KIND_LABEL, cleanContext };
