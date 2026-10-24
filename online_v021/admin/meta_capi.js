'use strict';
// R181 · META CONVERSIONS API (servidor → Meta). O pixel do navegador perde parte dos eventos (no teste de 23/10:
// pixel contou 10, os registros mostraram 13 pessoas). O jogo manda o MESMO evento pelo pixel e por aqui, com o mesmo
// event_id: a Meta deduplica (conta uma vez só).
//
// Regras:
//   · DESLIGADO sem META_CAPI_TOKEN (variável de ambiente do Render). O token NUNCA vai no código, no jogo nem em log.
//   · Só envia se a pessoa ACEITOU os cookies no aviso (LGPD), igual ao pixel do navegador.
//   · Dados mandados: nome do evento, horário, event_id, IP e navegador do pedido (exigidos pela Meta para casar a
//     visita) e os cookies _fbp/_fbc do próprio pixel. Nada de e-mail, nome, apelido ou id de conta.
//   · META_CAPI_TEST_CODE (opcional): código do "Testar eventos" do Gerenciador de Eventos (só para conferir).
//   · Um event_id é mandado uma vez só (o navegador pode reenviar o lote).
const DEFAULT_PIXEL = '1131165439457023';
const ALLOWED = new Set(['JogoCarregado', 'EntrouConvidado', 'CompleteRegistration', 'PrimeiraPartida', 'PartidaConcluida']);

class MetaCapi {
  constructor({ env = process.env, fetchImpl = (typeof fetch === 'function' ? fetch : null), now = () => Date.now(), log = console } = {}) {
    this.token = String(env.META_CAPI_TOKEN || '').trim();
    this.pixel = String(env.META_PIXEL_ID || DEFAULT_PIXEL).trim();
    this.testCode = String(env.META_CAPI_TEST_CODE || '').trim();
    this.version = String(env.META_CAPI_VERSION || 'v21.0').trim();
    this.site = String(env.META_CAPI_SITE_URL || 'https://jogar.fraihaxadrez.com/').trim();
    this.fetch = fetchImpl; this.now = now; this.log = log;
    this.sent = new Set(); this.order = [];
    this.stats = { sent: 0, failed: 0, skipped_consent: 0, disabled: 0 };
  }
  enabled() { return !!(this.token && /^\d{6,20}$/.test(this.pixel) && this.fetch); }
  payload(ev) {
    const user = { client_ip_address: ev.ip, client_user_agent: ev.ua };
    if (ev.fbp) user.fbp = ev.fbp;
    if (ev.fbc) user.fbc = ev.fbc;
    const body = { data: [{ event_name: ev.name, event_time: Math.floor(this.now() / 1000), event_id: ev.id, action_source: 'website',
      event_source_url: this.site, user_data: user, custom_data: ev.params || {} }] };
    if (this.testCode) body.test_event_code = this.testCode;
    return body;
  }
  async send(ev) {
    if (!ev || !ALLOWED.has(ev.name) || !ev.id) return false;
    if (!this.enabled()) { this.stats.disabled++; return false; }
    if (ev.consent !== true) { this.stats.skipped_consent++; return false; }
    if (this.sent.has(ev.id)) return false;
    this.sent.add(ev.id); this.order.push(ev.id);
    if (this.order.length > 20000) this.sent.delete(this.order.shift());
    const url = `https://graph.facebook.com/${this.version}/${this.pixel}/events?access_token=${encodeURIComponent(this.token)}`;
    try {
      const r = await this.fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(this.payload(ev)) });
      if (!r.ok) { this.stats.failed++; this.log.error('[meta-capi] recusado', r.status, ev.name); return false; }   // sem token/url no log
      this.stats.sent++; return true;
    } catch (e) { this.stats.failed++; this.log.error('[meta-capi] falhou', ev.name, e && e.name); return false; }
  }
}
module.exports = { MetaCapi, ALLOWED };
