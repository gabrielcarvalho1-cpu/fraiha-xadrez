'use strict';
// R31 · Identidade cosmética da conta: avatar, ícone (selo), título e moldura.
// O SERVIDOR decide o que pode ser usado, pelos direitos da conta (entitlements) e pela escada de
// bots (bot_progress). Só aparência: nada aqui altera PL, matchmaking, tempo, regras ou resultado.
const LADDER = require('../../bot/bot_ladder.json');
const ShopCatalog = require('../economy/store_catalog');   // R116 · itens da Loja de Coroas

const FREE_AVATARS = ['warrior', 'archer', 'peao_branco', 'peao_negro'];
const LEGACY_AVATARS = ['mage', 'paladin'];            // recompensas antigas: quem já tem continua exibindo
const FOUNDER_AVATARS = ['fundador'];
const CLUB_AVATARS = ['club_avatar_a', 'club_avatar_b', 'club_avatar_c'];
const LADDER_AVATARS = {};                              // avatar_id -> bot_id
for (const b of LADDER.bots) if (b.reward && b.reward.type === 'avatar') LADDER_AVATARS[b.reward.id] = b.id;
const ALL_AVATARS = [...FREE_AVATARS, ...LEGACY_AVATARS, ...Object.keys(LADDER_AVATARS), ...FOUNDER_AVATARS, ...CLUB_AVATARS];

const BADGES = ['', 'fundador', 'club_a', 'club_b', 'club_c'];
const SHOP_TITLES = ShopCatalog.ofKind('title');        // R116 · comprados com Coroas (para sempre)
const TITLES = ['', 'fundador', 'lendario', 'club', ...SHOP_TITLES];   // R103 · lendario = Fundador Lendário
const SHOP_FRAMES = ShopCatalog.ofKind('frame');        // R116 · molduras da Loja de Coroas
const FRAMES = ['liga', 'club', 'fundador', ...SHOP_FRAMES];

const need = (kind, id) => {
  if (!id || id === 'liga') return '';
  if (ShopCatalog.BY_ID[id] && ShopCatalog.BY_ID[id].kind === kind) return 'shop';
  if (id === 'lendario') return 'legend';
  if (id === 'fundador') return 'founder';
  if (kind === 'badge' && id.startsWith('club_')) return 'club';
  if (id === 'club') return 'club';
  return '';
};
// 'shop' (comprado na Loja de Coroas): a posse é conferida no validate (owned); depois de usado, é para sempre.
const has = (req, ent, owned, id) => req === '' || (req === 'shop' ? (owned === undefined || (Array.isArray(owned) && owned.includes(id))) : req === 'founder' ? !!(ent && ent.is_founder)
  : req === 'legend' ? !!(ent && ent.is_founder && ent.founder_tier === 'legend') : !!(ent && ent.club_active));

// Valida um pedido acct_set_cosmetics. ent = getEntitlements; defeated = bots vencidos (ou null se a
// escada não estiver configurada no banco). Devolve { ok, values } ou { error, code, field }.
function validate(m, ent, defeated, owned = []) {
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
    if (need(kind, v) === 'shop' && !has('shop', ent, owned || [], v)) return { error: 'Compre este item na Loja de Coroas.', code: 'cosmetic_locked', field };
    if (!has(need(kind, v), ent, owned || [], v)) return { error: 'Item exclusivo (' + ({ founder: 'Pacote Fundador', legend: 'Fundador Lendário' }[need(kind, v)] || 'Club FRAIHA') + ').', code: 'cosmetic_locked', field };
    out[field] = v;
  }
  if (!Object.keys(out).length) return { error: 'Nada para alterar.', code: 'cosmetic_invalid' };
  return { ok: true, values: out };
}

// O que os OUTROS jogadores veem: itens guardados, mas só enquanto o direito estiver ativo
// (Club vencido → some o selo/moldura do Club; a escolha fica salva para quando voltar).
function effective(p, ent) {
  const active = ent ? { is_founder: !!ent.is_founder, founder_tier: ent.founder_tier || null, club_active: !!ent.club_active && (!ent.club_expires_at || new Date(ent.club_expires_at) > new Date()) } : { is_founder: false, club_active: false };
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

// R41 · Parte pública da identidade que viaja para os outros jogadores (mesa, convite, festa, DM).
// Recebe ws.identity ({badge,title,frame,founder,club}) ou um perfil público (pub) e normaliza.
// R150 · foto de perfil (profiles.avatar_url, bucket público "avatars"): viaja junto para os outros jogadores
// verem a foto (antes só o avatar do catálogo ia). Só URL http(s) curta; qualquer outra coisa = sem foto.
function photoUrl(u) {
  u = typeof u === 'string' ? u : '';
  return /^(https?|memory):\/\/[^\s"'<>]{1,400}$/.test(u) ? u : null;
}
function look(o) {
  o = o || {};
  return { badge: BADGES.includes(o.badge) ? o.badge : '', title: TITLES.includes(o.title) ? o.title : '',
    frame: FRAMES.includes(o.frame) ? o.frame : 'liga', founder: !!o.founder, club: !!o.club, avatar_url: photoUrl(o.avatar_url) };
}

module.exports = { look, photoUrl, validate, effective, SHOP_TITLES, FREE_AVATARS, LEGACY_AVATARS, FOUNDER_AVATARS, CLUB_AVATARS, LADDER_AVATARS, ALL_AVATARS, BADGES, TITLES, FRAMES };
