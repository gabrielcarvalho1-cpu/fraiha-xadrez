'use strict';
// R176.8 · SUPORTE. O jogador manda uma mensagem (reclamação, sugestão, dúvida, problema no jogo, pagamento) pela tela
// SUPORTE; ela cai no Admin → Suporte, onde o dono responde. A resposta aparece em MEUS TICKETS e chega na hora se o
// jogador estiver online (ticket_update). Só contas (convidado não manda: precisa de alguém para responder).
// Banco: public.support_tickets (migração 0029). Sem a tabela, o ticket vai para o log do servidor e o jogador é
// avisado — nunca se perde em silêncio. Limites: 5 tickets por hora e 20 por dia por conta.
const CATEGORIES = ['reclamacao', 'sugestao', 'duvida', 'problema', 'pagamento'];
const CATEGORY_LABEL = { reclamacao: 'Reclamação', sugestao: 'Sugestão', duvida: 'Dúvida', problema: 'Problema no jogo', pagamento: 'Pagamento' };
const STATUSES = ['open', 'answered', 'closed'];
const HOUR = 3600e3, DAY = 86400e3, PER_HOUR = 5, PER_DAY = 20;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const missing = e => /42P01|42703|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const clean = (s, n) => String(s === undefined || s === null ? '' : s).replace(/\r\n/g, '\n').replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '').trim().slice(0, n);

function cleanContext(c) {
  const out = {};
  if (!c || typeof c !== 'object') return out;
  for (const k of ['platform', 'version', 'screen', 'mobile']) if (c[k] !== undefined) out[k] = typeof c[k] === 'string' ? c[k].slice(0, 60) : !!c[k];
  return out;
}
// o que o jogador vê dos próprios tickets (sem quem respondeu)
const publicView = t => ({ ticket_id: t.ticket_id, category: t.category, category_label: CATEGORY_LABEL[t.category] || t.category, subject: t.subject || '',
  message: t.message, status: t.status, reply: t.reply || '', replied_at: t.replied_at || null, created_at: t.created_at });

class Tickets {
  constructor({ backend, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.now = now; this.log = log;
    this.rate = new Map();   // uid -> [ts]
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.createTicket); }
  send(ws, m) { this.backend.send(ws, m); }

  // ---------- jogo ----------
  async handle(ws, m) {
    const a = String(m.type || '');
    const uid = ws.identity && ws.identity.id;
    const fail = (message, code) => this.send(ws, { type: 'ticket_error', message, code });
    if (!uid || ws.identity.guest || !UUID.test(String(uid))) return fail('Entre na sua conta para falar com o suporte.', 'login_required');
    if (a === 'ticket_send') return this.file(ws, uid, m, fail);
    if (a === 'ticket_list') return this.sendList(ws, uid);
    return fail('Pedido inválido.', 'invalid');
  }

  async file(ws, uid, m, fail) {
    const category = String(m.category || '');
    const subject = clean(m.subject, 80);
    const message = clean(m.message, 2000);
    if (!CATEGORIES.includes(category)) return fail('Escolha o tipo da mensagem.', 'invalid_category');
    if (message.length < 5) return fail('Escreva a sua mensagem (pelo menos 5 letras).', 'invalid_message');
    const now = this.now();
    const times = (this.rate.get(uid) || []).filter(t => now - t < DAY);
    if (times.filter(t => now - t < HOUR).length >= PER_HOUR || times.length >= PER_DAY) return fail('Você mandou muitas mensagens seguidas. Aguarde um pouco e tente de novo.', 'rate_limited');
    if (this.rate.size > 20000) for (const [k, v] of this.rate) if (!v.length || now - v[v.length - 1] > DAY) this.rate.delete(k);
    let nickname = '';
    try { const p = await this.store.getProfile(uid); nickname = p ? String(p.nickname || '') : ''; } catch { /* só exibição */ }
    const row = { user_id: uid, nickname: nickname.slice(0, 40), category, subject, message, context: cleanContext(m.context) };
    this.log('[suporte] ' + JSON.stringify({ uid, category, at: new Date(now).toISOString() }));
    if (this.ok()) {
      try {
        const t = await this.store.createTicket(row);
        times.push(now); this.rate.set(uid, times);
        this.send(ws, { type: 'ticket_ok', ticket: publicView(t) });
        return this.sendList(ws, uid);
      } catch (e) {
        if (!missing(e)) { console.error('[suporte] erro ao gravar', e && e.message); return fail('Não foi possível enviar agora. Tente de novo em instantes.', 'ticket_failed'); }
      }
    }
    this.log('[suporte-sem-tabela] ' + JSON.stringify(row));   // sem a 0029: fica no log do Render
    times.push(now); this.rate.set(uid, times);
    return fail('O suporte pelo jogo ainda não está ligado neste servidor. Sua mensagem ficou registrada; se for urgente, fale com a gente no Discord.', 'unavailable');
  }

  async sendList(ws, uid) {
    if (!this.ok() || !this.store.myTickets) return this.send(ws, { type: 'ticket_list', available: false, items: [] });
    try { const rows = await this.store.myTickets(uid, 20); return this.send(ws, { type: 'ticket_list', available: true, items: rows.map(publicView) }); }
    catch (e) { if (!missing(e)) console.error('[suporte] lista', e && e.message); return this.send(ws, { type: 'ticket_list', available: false, items: [] }); }
  }

  // ---------- Admin ----------
  async adminList(status) {
    if (!(this.store && this.store.listTickets)) return { available: false, error: 'migration_0029_missing' };
    try {
      const rows = await this.store.listTickets(STATUSES.includes(status) ? status : '', 200);
      return { available: true, items: rows.map(t => ({ ...publicView(t), user_id: t.user_id, nickname: t.nickname || '?', context: t.context || {}, replied_by: t.replied_by || '' })),
        categories: CATEGORY_LABEL };
    } catch (e) { if (missing(e)) return { available: false, error: 'migration_0029_missing' }; throw e; }
  }
  // body: { reply?, status? } → { status, body }
  async adminUpdate(admin, id, b) {
    if (!UUID.test(String(id))) return { status: 400, body: { error: 'invalid_id' } };
    if (!(this.store && this.store.updateTicket)) return { status: 503, body: { error: 'migration_0029_missing' } };
    const patch = { updated_at: new Date(this.now()).toISOString() };
    if (b.reply !== undefined) {
      const reply = clean(b.reply, 2000);
      if (reply.length < 2) return { status: 400, body: { error: 'invalid_reply' } };
      Object.assign(patch, { reply, status: 'answered', replied_by: String(admin.name || admin.id || 'admin').slice(0, 60), replied_at: patch.updated_at });
    }
    if (b.status !== undefined) {
      if (!STATUSES.includes(String(b.status))) return { status: 400, body: { error: 'invalid_status' } };
      patch.status = String(b.status);
    }
    if (Object.keys(patch).length < 2) return { status: 400, body: { error: 'nothing_to_change' } };
    let t;
    try { t = await this.store.updateTicket(id, patch); }
    catch (e) { if (missing(e)) return { status: 503, body: { error: 'migration_0029_missing' } }; throw e; }
    if (!t) return { status: 404, body: { error: 'not_found' } };
    // jogador online: a resposta chega na hora
    if (patch.reply && this.backend.socketsOf) for (const ws of this.backend.socketsOf(t.user_id)) this.send(ws, { type: 'ticket_update', ticket: publicView(t) });
    return { status: 200, body: { ticket: t } };
  }
}
module.exports = { Tickets, CATEGORIES, CATEGORY_LABEL, STATUSES, publicView };
