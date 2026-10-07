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

// Ritmos (fila por ritmo) do Ranked e do Casual. O servidor é a fonte de verdade: o jogo só mostra os ritmos
// ABERTOS (lista enviada no acct_state/guest_state e nos avisos 'ranked_modes'/'casual_modes').
// Fila aberta = família ON E ritmo ON. O Casual tem as MESMAS 4 filas reais do servidor (casual_3/5/10/20min,
// ranked/config.js CASUAL_MODES; o jogador escolhe o ritmo na tela JOGAR ONLINE).
const RANKED_MODES = {
  ranked_3min: { label: 'RELÂMPAGO', minutes: 3, word: 'relampago' },
  ranked_5min: { label: 'RÁPIDA', minutes: 5, word: 'rapida' },
  ranked_10min: { label: 'NORMAL', minutes: 10, word: 'normal' },
  ranked_20min: { label: 'CONVENCIONAL', minutes: 20, word: 'convencional' },
};
const CASUAL_MODES = {
  casual_3min: { label: 'RELÂMPAGO', minutes: 3, word: 'relampago' },
  casual_5min: { label: 'RÁPIDA', minutes: 5, word: 'rapida' },
  casual_10min: { label: 'NORMAL', minutes: 10, word: 'normal' },
  casual_20min: { label: 'CONVENCIONAL', minutes: 20, word: 'convencional' },
};
const MODE_SETS = { ranked: RANKED_MODES, casual: CASUAL_MODES };
const BOOT_ENV = { ranked: 'FRAIHA_RANKED_MODES_OPEN', casual: 'FRAIHA_CASUAL_MODES_OPEN' };
// Ritmos abertos ao SUBIR o servidor (o estado do Admin é em memória: um reinício volta a este padrão).
// FRAIHA_RANKED_MODES_OPEN="ranked_5min,ranked_10min" / FRAIHA_CASUAL_MODES_OPEN="casual_5min"
// (sem a variável = os 4 abertos; valor inválido é ignorado).
function bootModes(env, family = 'ranked') {
  const raw = env && env[BOOT_ENV[family]];
  if (raw === undefined || raw === null || String(raw).trim() === '') return null;
  const want = String(raw).split(',').map(x => x.trim()).filter(x => MODE_SETS[family][x]);
  return new Set(want);
}
const bootRankedModes = env => bootModes(env, 'ranked');

class ModeControls {
  constructor({ now = () => Date.now(), env = {} } = {}) {
    this.now = now;
    this.state = new Map(Object.keys(FAMILIES).map(f => [f, { enabled: true, changed_at: null, changed_by: null, reason: '' }]));
    this.modes = {};
    for (const fam of Object.keys(MODE_SETS)) {
      const boot = bootModes(env, fam);
      this.modes[fam] = new Map(Object.keys(MODE_SETS[fam]).map(m => [m, { enabled: boot ? boot.has(m) : true, changed_at: null, changed_by: null, reason: boot ? `padrão do servidor (${BOOT_ENV[fam]})` : '' }]));
    }
    this.rankedModes = this.modes.ranked;   // compatibilidade
    this.listeners = [];
  }
  static modeIds(family) { return MODE_SETS[family] ? Object.keys(MODE_SETS[family]) : []; }
  static rankedModeIds() { return ModeControls.modeIds('ranked'); }
  static hasModes(family) { return !!MODE_SETS[family]; }
  static bootEnv(family) { return BOOT_ENV[family] || null; }
  // Ritmo aberto para NOVAS entradas/pareamentos (família ON e ritmo ON).
  isModeOpen(family, mode) { const m = this.modes[family]; const s = m && m.get(mode); return this.isOpen(family) && !!s && s.enabled; }
  openModes(family) { return ModeControls.modeIds(family).filter(m => this.isModeOpen(family, m)); }
  setMode(family, mode, enabled, actor, reason = '') {
    const map = this.modes[family], cur = map && map.get(mode);
    if (!cur) { const e = new Error('unknown_mode'); e.code = 'unknown_mode'; throw e; }
    const before = { ...cur };
    const after = { enabled: !!enabled, changed_at: new Date(this.now()).toISOString(), changed_by: actor || null, reason: String(reason || '').slice(0, 300) };
    map.set(mode, after);
    for (const fn of this.listeners) { try { fn(family, this.state.get(family), null, mode, after); } catch (e) { console.error('[admin] control listener', e && e.message); } }
    return { before, after };
  }
  modesSnapshot(family) {
    return Object.entries(MODE_SETS[family] || {}).map(([id, d]) => ({ mode: id, label: d.label, minutes: d.minutes, word: d.word, ...this.modes[family].get(id), open: this.isModeOpen(family, id) }));
  }
  isRankedModeOpen(mode) { return this.isModeOpen('ranked', mode); }
  openRankedModes() { return this.openModes('ranked'); }
  setRankedMode(mode, enabled, actor, reason = '') { return this.setMode('ranked', mode, enabled, actor, reason); }
  rankedModesSnapshot() { return this.modesSnapshot('ranked'); }
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
module.exports = { ModeControls, FAMILIES, RANKED_MODES, CASUAL_MODES, CLOSED_MESSAGE };
