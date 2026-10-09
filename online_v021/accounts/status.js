'use strict';
// R55 · STATUS do perfil (frase curta embaixo do cartão da Home). Fica em profiles.settings.status
// (coluna jsonb que existe desde a 0001: nenhuma migração). O servidor limpa e limita o texto; o cliente
// só exibe. Vazio = o jogo mostra o texto padrão.
const MAX = 80;

// Remove controle, formatação invisível (zero-width, bidi), uso privado e substitutos; junta espaços.
function sanitize(v) {
  if (v !== undefined && v !== null && typeof v !== 'string') return { error: 'Status inválido.', code: 'status_invalid' };
  let s = String(v || '').normalize('NFC');
  s = s.replace(/[\p{C}]/gu, ' ').replace(/\s+/g, ' ').trim();
  if ([...s].length > MAX) return { error: `Status muito longo (máximo ${MAX} caracteres).`, code: 'status_too_long' };
  return { ok: true, status: s };
}

function of(profile) {
  const st = profile && profile.settings && profile.settings.status;
  return typeof st === 'string' ? st : '';
}

module.exports = { MAX, sanitize, of };
