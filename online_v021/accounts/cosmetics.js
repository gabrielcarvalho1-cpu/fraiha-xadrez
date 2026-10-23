'use strict';
// R31 · Identidade cosmética da conta: avatar, ícone (selo), título e moldura.
// O SERVIDOR decide o que pode ser usado, pelos direitos da conta (entitlements) e pela escada de
// bots (bot_progress). Só aparência: nada aqui altera PL, matchmaking, tempo, regras ou resultado.
const LADDER = require('../../bot/bot_ladder.json');
const ShopCatalog = require('../economy/store_catalog');   // R116 · itens da Loja de Coroas

const FREE_AVATARS = ['warrior', 'archer', 'peao_branco', 'peao_negro', 'av_peao_dourado', 'av_torre_marmore', 'av_bispo_marmore', 'av_cavalo_marmore', 'av_heroi', 'av_principe_dourado', 'av_tab_mogno', 'av_tab_torneio_pixel', 'av_tab_salao_pixel', 'av_tab_oficina_pixel'];   // R163 · +6 grátis
const LEGACY_AVATARS = ['mage', 'paladin'];            // recompensas antigas: quem já tem continua exibindo
const FOUNDER_AVATARS = ['fundador', 'av_mestre_dourado', 'av_mestre_sombras', 'av_grao_mestre', 'av_rainha_invernal', 'av_rei_dourado_coroa', 'av_rainha_purpura_coroa', 'av_rainha_gelo', 'av_rainha_cristal', 'av_rei_do_trono'];
const LEGEND_AVATARS = ['av_lenda_mistica', 'av_rei_rubi_coroa'];   // R163 · só Fundador Lendário
const CLUB_AVATARS = ['club_avatar_a', 'club_avatar_b', 'club_avatar_c', 'av_rainha_purpura', 'av_dama_esmeralda', 'av_dama_bispo', 'av_dama_torre', 'av_mestre_purpura', 'av_rainha_neon', 'av_tab_cidade_neon', 'av_rainha_punk', 'av_bispa_esmeralda', 'av_rainha_floresta', 'av_rainha_neon_punk', 'av_bispa_ruiva'];
// R163 · avatares da Loja de Coroas e do Passe: a conta precisa TER o item (crown_items), para sempre
const OWNED_AVATARS = [...ShopCatalog.ofKind('avatar'), ...ShopCatalog.PASS_AVATARS.map(a => a.id)];
const LADDER_AVATARS = {};                              // avatar_id -> bot_id
for (const b of LADDER.bots) if (b.reward && b.reward.type === 'avatar') LADDER_AVATARS[b.reward.id] = b.id;
const ALL_AVATARS = [...FREE_AVATARS, ...LEGACY_AVATARS, ...Object.keys(LADDER_AVATARS), ...FOUNDER_AVATARS, ...LEGEND_AVATARS, ...CLUB_AVATARS, ...OWNED_AVATARS];

const BADGES = ['', 'fundador', 'club_a', 'club_b', 'club_c'];
const SHOP_TITLES = ShopCatalog.ofKind('title');        // R116 · comprados com Coroas (para sempre)
const PASS_TITLES = ShopCatalog.PASS_TITLES.map(t => t.id);   // R178 · títulos do Passe (a conta precisa TER o item)
const TITLES = ['', 'fundador', 'lendario', 'club', ...SHOP_TITLES, ...PASS_TITLES];   // R103 · lendario = Fundador Lendário
const SHOP_FRAMES = ShopCatalog.ofKind('frame');        // R116 · molduras da Loja de Coroas
// R166 · molduras de ELO: liberadas ao alcançar a liga (maior liga já alcançada em qualquer ritmo do Ranked)
const ELO_FRAMES = ['elo_madeira', 'elo_ferro', 'elo_bronze', 'elo_prata', 'elo_ouro', 'elo_platina', 'elo_esmeralda', 'elo_diamante', 'elo_mestre', 'elo_grande_mestre', 'elo_challenger'];
const FRAMES = ['liga', 'club', 'fundador', ...ELO_FRAMES, ...SHOP_FRAMES];

const need = (kind, id) => {
  if (!id || id === 'liga') return '';
  if (ShopCatalog.BY_ID[id] && ShopCatalog.BY_ID[id].kind === kind) return 'shop';
  if (kind === 'title' && ShopCatalog.PASS_TITLE_BY_ID[id]) return 'shop';   // R178 · ganho no Passe: precisa ter
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
function validate(m, ent, defeated, owned = [], highest = 0) {
  const out = {};
  if (m.avatar_id !== undefined) {
    const a = String(m.avatar_id || '');
    if (!ALL_AVATARS.includes(a)) return { error: 'Avatar desconhecido.', code: 'cosmetic_invalid', field: 'avatar_id' };
    if (FOUNDER_AVATARS.includes(a) && !(ent && ent.is_founder)) return { error: 'Avatar exclusivo do Pacote Fundador.', code: 'cosmetic_locked', field: 'avatar_id' };
    if (CLUB_AVATARS.includes(a) && !(ent && ent.club_active)) return { error: 'Avatar exclusivo do Club FRAIHA.', code: 'cosmetic_locked', field: 'avatar_id' };
    if (LEGEND_AVATARS.includes(a) && !(ent && ent.is_founder && ent.founder_tier === 'legend')) return { error: 'Avatar exclusivo do Fundador Lendário.', code: 'cosmetic_locked', field: 'avatar_id' };
    if (OWNED_AVATARS.includes(a) && !(Array.isArray(owned) && owned.includes(a))) return { error: ShopCatalog.BY_ID[a] ? 'Compre este avatar na Loja de Coroas.' : 'Avatar do Passe da Temporada.', code: 'cosmetic_locked', field: 'avatar_id' };
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
    if (need(kind, v) === 'shop' && !has('shop', ent, owned || [], v)) return { error: ShopCatalog.PASS_TITLE_BY_ID[v] ? 'Ganhe este título no Passe da Temporada.' : 'Compre este item na Loja de Coroas.', code: 'cosmetic_locked', field };
    if (kind === 'frame' && ELO_FRAMES.includes(v) && (Number(highest) || 0) < ELO_FRAMES.indexOf(v)) return { error: 'Moldura liberada ao alcançar essa liga no Ranked.', code: 'cosmetic_locked', field };
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
  if ((FOUNDER_AVATARS.includes(avatar) && !active.is_founder) || (CLUB_AVATARS.includes(avatar) && !active.club_active)
    || (LEGEND_AVATARS.includes(avatar) && !(active.is_founder && active.founder_tier === 'legend'))) avatar = 'warrior';
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

module.exports = { look, photoUrl, validate, effective, SHOP_TITLES, FREE_AVATARS, LEGACY_AVATARS, FOUNDER_AVATARS, LEGEND_AVATARS, CLUB_AVATARS, OWNED_AVATARS, ELO_FRAMES, LADDER_AVATARS, ALL_AVATARS, BADGES, TITLES, FRAMES };
