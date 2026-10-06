'use strict';
// FRAIHA Admin · controle de ENTRADA em modos (filas / novas partidas). Autoridade: SERVIDOR.
// Regra (V1): DESATIVAR um modo impede NOVAS entradas e NOVOS pareamentos/partidas; quem já estava
// esperando na fila sai dela com aviso ("fila desativada"); partidas EM ANDAMENTO nunca são tocadas.
// Estado em memória do processo (instância única no Render): reinício volta tudo para ATIVO.
// Preparado para crescer: cada modo tem um registro com quem/quando/motivo; agenda/eventos/manutenção
// entram como novos campos (schedule) sem mudar o contrato de leitura.
const FAMILIES = {
  ranked: { label: 'Ranked', entry: 'fila Ranked (3/5/10/20 min)' },
  casual: { label: 'Casual', entry: 'fila Casual + convites de xadrez entre amigos' },
  xeque: { label: 'XEQUE', entry: 'convites para mesa de XEQUE' },
  marcha: { label: 'MARCHA REAL', entry: 'convites para mesa de MARCHA REAL' },
};

class ModeControls {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.state = new Map(Object.keys(FAMILIES).map(f => [f, { enabled: true, changed_at: null, changed_by: null, reason: '' }]));
    this.listeners = [];
  }
  static families() { return Object.keys(FAMILIES); }
  static label(f) { return FAMILIES[f] ? FAMILIES[f].label : f; }
  isOpen(family) { const s = this.state.get(family); return !s || s.enabled; }
  get(family) { return this.state.get(family) || null; }
  // Devolve {before, after}. Lança erro para família desconhecida (nunca cria estado novo).
  set(family, enabled, actor, reason = '') {
    const cur = this.state.get(family);
    if (!cur) { const e = new Error('unknown_family'); e.code = 'unknown_family'; throw e; }
    const before = { ...cur };
    const after = { enabled: !!enabled, changed_at: new Date(this.now()).toISOString(), changed_by: actor || null, reason: String(reason || '').slice(0, 300) };
    this.state.set(family, after);
    for (const fn of this.listeners) { try { fn(family, after, before); } catch (e) { console.error('[admin] control listener', e && e.message); } }
    return { before, after };
  }
  onChange(fn) { this.listeners.push(fn); }
  snapshot() {
    const out = {};
    for (const [f, s] of this.state) out[f] = { family: f, label: FAMILIES[f].label, entry: FAMILIES[f].entry, ...s, schedule: [] };
    return out;
  }
}

const CLOSED_MESSAGE = 'Este modo está temporariamente desativado. Tente novamente mais tarde.';
module.exports = { ModeControls, FAMILIES, CLOSED_MESSAGE };
