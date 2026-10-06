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

// Ritmos do Ranked (fila por ritmo). O servidor é a fonte de verdade: o jogo só mostra os ritmos ABERTOS
// (lista enviada no acct_state e no aviso 'ranked_modes'). Fila Ranked aberta = família ON E ritmo ON.
const RANKED_MODES = {
  ranked_3min: { label: 'RELÂMPAGO', minutes: 3, word: 'relampago' },
  ranked_5min: { label: 'RÁPIDA', minutes: 5, word: 'rapida' },
  ranked_10min: { label: 'NORMAL', minutes: 10, word: 'normal' },
  ranked_20min: { label: 'CONVENCIONAL', minutes: 20, word: 'convencional' },
};
// Ritmos abertos ao SUBIR o servidor (o estado do Admin é em memória: um reinício volta a este padrão).
// FRAIHA_RANKED_MODES_OPEN="ranked_5min,ranked_10min" (sem a variável = os 4 abertos; valor inválido é ignorado).
function bootRankedModes(env) {
  const raw = env && env.FRAIHA_RANKED_MODES_OPEN;
  if (raw === undefined || raw === null || String(raw).trim() === '') return null;
  const want = String(raw).split(',').map(x => x.trim()).filter(x => RANKED_MODES[x]);
  return new Set(want);
}

class ModeControls {
  constructor({ now = () => Date.now(), env = {} } = {}) {
    this.now = now;
    this.state = new Map(Object.keys(FAMILIES).map(f => [f, { enabled: true, changed_at: null, changed_by: null, reason: '' }]));
    const boot = bootRankedModes(env);
    this.rankedModes = new Map(Object.keys(RANKED_MODES).map(m => [m, { enabled: boot ? boot.has(m) : true, changed_at: null, changed_by: null, reason: boot ? 'padrão do servidor (FRAIHA_RANKED_MODES_OPEN)' : '' }]));
    this.listeners = [];
  }
  static rankedModeIds() { return Object.keys(RANKED_MODES); }
  // Ritmo do Ranked aberto para NOVAS entradas/pareamentos (família ON e ritmo ON).
  isRankedModeOpen(mode) { const s = this.rankedModes.get(mode); return this.isOpen('ranked') && !!s && s.enabled; }
  openRankedModes() { return Object.keys(RANKED_MODES).filter(m => this.isRankedModeOpen(m)); }
  setRankedMode(mode, enabled, actor, reason = '') {
    const cur = this.rankedModes.get(mode);
    if (!cur) { const e = new Error('unknown_mode'); e.code = 'unknown_mode'; throw e; }
    const before = { ...cur };
    const after = { enabled: !!enabled, changed_at: new Date(this.now()).toISOString(), changed_by: actor || null, reason: String(reason || '').slice(0, 300) };
    this.rankedModes.set(mode, after);
    for (const fn of this.listeners) { try { fn('ranked', this.state.get('ranked'), null, mode, after); } catch (e) { console.error('[admin] control listener', e && e.message); } }
    return { before, after };
  }
  rankedModesSnapshot() {
    return Object.entries(RANKED_MODES).map(([id, d]) => ({ mode: id, label: d.label, minutes: d.minutes, word: d.word, ...this.rankedModes.get(id), open: this.isRankedModeOpen(id) }));
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
module.exports = { ModeControls, FAMILIES, RANKED_MODES, CLOSED_MESSAGE };
