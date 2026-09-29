'use strict';
// Configuração central do Ranked. Tempos de teste só via variáveis de ambiente de desenvolvimento.
const MODES = {
  ranked_3min:  { name: 'Relâmpago',    minutes: 3 },
  ranked_5min:  { name: 'Rápida',       minutes: 5 },
  ranked_10min: { name: 'Normal',       minutes: 10 },
  ranked_20min: { name: 'Convencional', minutes: 20 },
};
// Casual: mesmos ritmos, filas próprias, sem PL.
const CASUAL_MODES = {
  casual_3min:  { name: 'Relâmpago',    minutes: 3 },
  casual_5min:  { name: 'Rápida',       minutes: 5 },
  casual_10min: { name: 'Normal',       minutes: 10 },
  casual_20min: { name: 'Convencional', minutes: 20 },
};
const ALL_MODES = { ...MODES, ...CASUAL_MODES };
const LEAGUES = ['Madeira','Ferro','Bronze','Prata','Ouro','Platina','Esmeralda','Diamante','Mestre','Grande Mestre','Challenger'];
const env = process.env;
const num = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
const CONFIG = {
  // Tempo base por modalidade; FRAIHA_TEST_BASE_MS substitui (somente testes).
  baseMs: mode => num(env.FRAIHA_TEST_BASE_MS, ALL_MODES[mode].minutes * 60000),
  startDelayMs: num(env.FRAIHA_RANKED_START_DELAY_MS, 3000),
  reconnectGraceMs: num(env.FRAIHA_RANKED_RECONNECT_MS, 60000),
  matchmaking: {
    initialPlWindow: 20,                                   // mesma liga, ±20 PL
    expandEveryMs: num(env.FRAIHA_MM_EXPAND_MS, 10000),    // a cada 10 s amplia
    expandStep: 40,                                        // +40 na faixa (liga*100+PL)
    maxWindow: 1100,                                       // acaba aceitando qualquer liga
  },
  tickMs: 200,
};
module.exports = { MODES, CASUAL_MODES, ALL_MODES, LEAGUES, CONFIG };
