'use strict';
// R31 · Identidade cosmética da conta: avatar, ícone (selo), título e moldura.
// O SERVIDOR decide o que pode ser usado, pelos direitos da conta (entitlements) e pela escada de
// bots (bot_progress). Só aparência: nada aqui altera PL, matchmaking, tempo, regras ou resultado.
const LADDER = require('../../bot/bot_ladder.json');

const FREE_AVATARS = ['warrior', 'archer', 'peao_branco', 'peao_negro'];
const LEGACY_AVATARS = ['mage', 'paladin'];            // recompensas antigas: quem já tem continua exibindo
const FOUNDER_AVATARS = ['fundador'];
const CLUB_AVATARS = ['club_avatar_a', 'club_avatar_b', 'club_avatar_c'];
const LADDER_AVATARS = {};                              // avatar_id -> bot_id
for (const b of LADDER.bots) if (b.reward && b.reward.type === 'avatar') LADDER_AVATARS[b.reward.id] = b.id;
const ALL_AVATARS = [...FREE_AVATARS, ...LEGACY_AVATARS, ...Object.keys(LADDER_AVATARS), ...FOUNDER_AVATARS, ...CLUB_AVATARS];

const BADGES = ['', 'fundador', 'club_a', 'club_b', 'club_c'];
const TITLES = ['', 'fundador', 'club'];
const FRAMES = ['liga', 'club', 'fundador'];

const need = (kind, id) => {
  if (!id || id === 'liga') return '';
  if (id === 'fundador') return 'founder';
  if (kind === 'badge' && id.startsWith('club_')) return 'club';
  if (id === 'club') return 'club';
  return '';
};
const has = (req, ent) => req === '' || (req === 'founder' ? !!(ent && ent.is_founder) : !!(ent && ent.club_active));

// Valida um pedido acct_set_cosmetics. ent = getEntitlements; defeated = bots vencidos (ou null se a
// escada não estiver configurada no banco). Devolve { ok, values } ou { error, code, field }.
function validate(m, ent, defeated) {
  const out = {};
  if (m.avatar_id !== undefined) {
    const a = String(m.avatar_id || '');
    if (!ALL_AVATARS.includes(a)) return { error: 'Avatar desconhecido.', code: 'cosmetic_invalid', field: 'avatar_id' };
    if (FOUNDER_AVATARS.includes(a) && !(ent && ent.is_founder)) return { error: 'Avatar exclusivo do Pacote Fundador.', code: 'cosmetic_locked', field: 'avatar_id' };
    if (CLUB_AVATARS.includes(a) && !(ent && ent.club_active)) return { error: 'Avatar exclusivo do Club FRAIHA.', code: 'cosmetic_locked', field: 'avatar_id' };
    if (LADDER_AVATARS[a]) {
      if (!defeated) return { error: 'Progresso dos bots indisponível no servidor.', code: 'not_configured', field: 'avatar_id' };
      if (!defeated.includes(LADDER_AVATARS[a])) return { error: 'Avatar ainda bloqueado: vença o bot da escada.', code: 'cosmetic_locked', field: 'avatar_id' };
    }
    out.avatar_id = a;
  }
  for (const [field, kind, list] of [['badge', 'badge', BADGES], ['title', 'title', TITLES], ['frame', 'frame', FRAMES]]) {
    if (m[field] === undefined) continue;
    const v = String(m[field] || (kind === 'frame' ? 'liga' : ''));
    if (!list.includes(v)) return { error: 'Opção inválida.', code: 'cosmetic_invalid', field };
    if (!has(need(kind, v), ent)) return { error: 'Item exclusivo (' + (need(kind, v) === 'founder' ? 'Pacote Fundador' : 'Club FRAIHA') + ').', code: 'cosmetic_locked', field };
    out[field] = v;
  }
  if (!Object.keys(out).length) return { error: 'Nada para alterar.', code: 'cosmetic_invalid' };
  return { ok: true, values: out };
}

// O que os OUTROS jogadores veem: itens guardados, mas só enquanto o direito estiver ativo
// (Club vencido → some o selo/moldura do Club; a escolha fica salva para quando voltar).
function effective(p, ent) {
  const active = ent ? { is_founder: !!ent.is_founder, club_active: !!ent.club_active && (!ent.club_expires_at || new Date(ent.club_expires_at) > new Date()) } : { is_founder: false, club_active: false };
  const pick = (kind, v, fallback) => (v && has(need(kind, v), active)) ? v : fallback;
  let avatar = p.avatar_id || 'warrior';
  if ((FOUNDER_AVATARS.includes(avatar) && !active.is_founder) || (CLUB_AVATARS.includes(avatar) && !active.club_active)) avatar = 'warrior';
  return {
    avatar_id: avatar,
    badge: pick('badge', p.profile_badge || '', ''),
    title: pick('title', p.profile_title || '', ''),
    frame: pick('frame', p.profile_frame === 'madeira' ? 'liga' : (p.profile_frame || 'liga'), 'liga'),
    founder: active.is_founder,
    club: active.club_active,
  };
}

module.exports = { validate, effective, FREE_AVATARS, LEGACY_AVATARS, FOUNDER_AVATARS, CLUB_AVATARS, LADDER_AVATARS, ALL_AVATARS, BADGES, TITLES, FRAMES };
