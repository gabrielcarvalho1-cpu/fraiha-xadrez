// FRAIHA Admin · telas. Regra: número só aparece quando o servidor o entrega; o que não existe aparece
// como INDISPONÍVEL com o motivo. Ação sem backend aparece desabilitada com "BACKEND NECESSÁRIO".
import { h, metricCard, statusBadge, stateBox, loadingCards, lineChart, confirmAction, entitlementDialog, crownsDialog, toast, unavailable,
  fmtInt, fmtDur, fmtDate, fmtAgo, FAMILY_LABEL, PLACE_LABEL } from '../ui.js';
import { ApiError } from '../api.js';

// Esqueleto comum: título + área de conteúdo + faixa de erro/dados antigos.
function frame(ctx, title, sub, initial) {
  const banner = h('div', { class: 'hidden', id: 'view-banner' });
  const body = h('div', { id: 'view-body' }, initial || loadingCards());
  ctx.el.replaceChildren(h('h1', {}, title), h('p', { class: 'sub' }, sub), banner, body);
  let had = false;
  return {
    show(...nodes) { had = true; banner.className = 'hidden'; body.replaceChildren(...nodes); },
    error(err, lastOk) {
      if (!had) { body.replaceChildren(stateBox('error', err.text), h('div', { style: 'text-align:center;margin-top:12px' }, h('button', { class: 'btn', onclick: ctx.refresh }, 'Tentar de novo'))); return; }
      banner.className = 'banner err';
      banner.textContent = `${err.text} Mostrando dados de ${lastOk ? new Date(lastOk).toLocaleTimeString('pt-BR') : 'antes'} (podem estar desatualizados).`;
    },
  };
}
const card = (label, m, o) => metricCard(label, m, o);
const pill = (on) => h('span', { class: 'badge ' + (on ? 'on' : 'off') }, on ? 'ATIVO' : 'DESATIVADO');

// ---------------------------------------------------------------- DASHBOARD
export function dashboard(ctx) {
  const f = frame(ctx, 'Dashboard', 'Saúde do jogo agora. Cada número diz de onde vem: REAL, PARCIAL (desde o último reinício do servidor) ou SEM DADOS.');
  return {
    error: f.error,
    async load() {
      const [o, lv] = await Promise.all([ctx.api.get('/admin/api/overview'), ctx.api.get('/admin/api/live?range=24h')]);
      if (!ctx.alive()) return;
      const c = o.cards;
      f.show(
        h('div', { class: 'grid' },
          card('Online agora', c.online_now, { hero: true }), card('Em partida', c.in_match), card('Home / Lobby', c.lobby), card('Em fila', c.in_queue),
          card('Partidas ativas', c.active_matches), card('Usuários cadastrados', c.registered_users), card('Novos hoje', c.new_users_today),
          card('Pico online hoje', c.peak_online_today), card('Tempo médio de fila', c.avg_queue_time, { fmt: fmtDur })),
        h('div', { class: 'split' },
          h('div', { class: 'panel' }, h('h2', {}, 'Jogadores online — últimas 24 h ', statusBadge('partial')),
            lineChart(lv.series, [{ key: 'online', label: 'online', color: '#d9b45a' }, { key: 'in_match', label: 'em partida', color: '#5b8def' }, { key: 'in_queue', label: 'em fila', color: '#3fbf7f' }],
              { empty: 'Sem amostras ainda: a série começa quando o servidor sobe (a cada 15 s).' }),
            h('p', { class: 'note dim' }, `Telemetria em memória desde ${fmtDate(o.tracking_since)}. Histórico durável precisa de migration (proposta).`)),
          h('div', { class: 'panel' }, h('h2', {}, 'Hoje'), h('div', { class: 'grid' },
            card('Partidas iniciadas', c.matches_started_today), card('Partidas concluídas', c.matches_finished_today), card('Abandonos', c.matches_abandoned_today), card('Usando Voice', c.voice_users)))),
        h('div', { class: 'panel' }, h('h2', {}, 'Ainda sem dados (dependem de instrumentação/backend)'),
          h('div', { class: 'grid' }, card('Jogadores únicos hoje', c.unique_players_today), card('Retorno de jogadores', c.returning_players), card('Plataforma', c.platform), card('Erros / reconexões', c.reconnects_errors))));
    },
  };
}

// ---------------------------------------------------------------- AO VIVO
export function live(ctx) {
  let range = '1h';
  const f = frame(ctx, 'Ao Vivo', 'Tela para deixar aberta durante campanhas: atualiza sozinha a cada 5 s.');
  const self = {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/live?range=' + range);
      if (!ctx.alive()) return;
      const n = d.now, R = m => ({ value: m, status: 'real', note: '' });
      const seg = h('div', { class: 'seg' }, ['1h', '6h', '24h'].map(x => h('button', { class: x === range ? 'on' : '', onclick: () => { range = x; ctx.refresh(); } }, x)),
        h('button', { disabled: true, title: 'Precisa de histórico durável (migration proposta)' }, '7 dias'), h('button', { disabled: true, title: 'Precisa de histórico durável (migration proposta)' }, '30 dias'));
      f.show(
        d.alerts.length ? h('div', {}, d.alerts.map(a => h('div', { class: 'banner ' + (a.level === 'error' ? 'err' : 'warn') }, '⚠ ' + a.text))) : '',
        h('div', { class: 'grid' }, card('Online agora', R(n.online), { hero: true }), card('Home / Lobby', R(n.lobby)), card('Em fila', R(n.in_queue)), card('Em partida', R(n.in_match)),
          card('Partidas ativas', R(n.matches)), card('Maior espera agora', n.longest_wait_ms === null ? { value: null, status: 'real', note: 'ninguém na fila' } : R(n.longest_wait_ms), { fmt: fmtDur }),
          card('Pico (hoje)', { value: d.peak.today, status: 'partial', note: d.peak.today_at ? 'às ' + fmtDate(d.peak.today_at) : 'desde ' + fmtDate(d.tracking_since) }), card('Usando Voice', R(n.voice))),
        h('div', { class: 'split' },
          h('div', { class: 'panel' }, h('div', { class: 'qhead' }, h('h2', {}, 'Ao longo do tempo'), seg),
            lineChart(d.series, [{ key: 'online', label: 'online', color: '#d9b45a' }, { key: 'in_match', label: 'em partida', color: '#5b8def' }, { key: 'in_queue', label: 'em fila', color: '#3fbf7f' }, { key: 'matches', label: 'partidas simultâneas', color: '#c084fc' }])),
          h('div', { class: 'panel' }, h('h2', {}, 'Distribuição por modo'),
            h('table', {}, h('thead', {}, h('tr', {}, h('th', {}, 'Modo'), h('th', {}, 'Na fila'), h('th', {}, 'Jogando'), h('th', {}, 'Partidas'))),
              h('tbody', {}, Object.entries(d.by_family).map(([k, v]) => h('tr', {}, h('td', {}, FAMILY_LABEL[k]), h('td', {}, v.queue === null ? h('span', { class: 'dim' }, 'convite') : fmtInt(v.queue)), h('td', {}, fmtInt(v.players)), h('td', {}, fmtInt(v.matches)))))))),
        h('div', { class: 'panel' }, h('h2', {}, 'Funil da campanha (anúncio → cadastro → online → fila → partida)'),
          h('p', { class: 'muted' }, 'Online, fila e partidas já são reais (acima). Cliques/anúncios e cadastros por hora: ', unavailable('INDISPONÍVEL — PRECISA INSTRUMENTAÇÃO (UTM no cadastro + eventos)'))));
    },
  };
  return self;
}

// ---------------------------------------------------------------- FILAS
export function queues(ctx) {
  const f = frame(ctx, 'Filas e modos', 'Ativar/desativar é aplicado e validado no SERVIDOR. Desativar NÃO encerra partidas em andamento.');
  const canWrite = ctx.session.admin.perms.includes('queues.write');
  async function toggle(q) {
    const enable = !q.enabled;
    const ok = await confirmAction({ title: `${enable ? 'Ativar' : 'Desativar'} ${FAMILY_LABEL[q.family]}`,
      body: enable ? `Volta a aceitar ${q.entry}.` : `Bloqueia ${q.entry}. Quem estiver esperando sai da fila com aviso. Partidas em andamento continuam até o fim.`,
      confirmWord: q.family, actionLabel: enable ? 'Ativar' : 'Desativar', danger: !enable });
    if (!ok || !ctx.alive()) return;   // confirmação fechada ou sessão encerrada: nada é enviado
    try {
      const r = await ctx.api.post('/admin/api/queues/' + q.family, { enabled: enable, reason: ok.reason, confirm: ok.confirm });
      toast(r.changed ? `${FAMILY_LABEL[q.family]} ${enable ? 'ATIVADO' : 'DESATIVADO'} pelo servidor · registrado no Admin Log` : 'Nada mudou (já estava assim) · registrado no Admin Log');
    } catch (e) { if (!ctx.alive() || (e instanceof ApiError && e.kind === 'revoked')) return; toast(e instanceof ApiError ? e.text : 'Falha ao aplicar', 'err'); }
    if (ctx.alive()) ctx.refresh();
  }
  // Ritmo (Ranked e Casual): o jogo deixa de MOSTRAR o ritmo fechado (servidor é a fonte de verdade).
  const SCREEN = { ranked: 'JOGAR RANQUEADO', casual: 'JOGAR ONLINE' };
  const NONE = { ranked: 'RANQUEADA INDISPONÍVEL', casual: 'CASUAL INDISPONÍVEL' };
  async function toggleMode(q, m) {
    const enable = !m.enabled, fam = FAMILY_LABEL[q.family].toUpperCase();
    const ok = await confirmAction({ title: `${enable ? 'Ativar' : 'Desativar'} ${fam} ${m.label} (${m.minutes} min)`,
      body: enable ? `O ritmo volta a aparecer na tela ${SCREEN[q.family]} e aceita entrada na fila.` : `Some da tela ${SCREEN[q.family]} dos jogadores. Quem estiver esperando neste ritmo sai da fila com aviso. Partidas em andamento continuam.`,
      confirmWord: m.word, actionLabel: enable ? 'Ativar ritmo' : 'Desativar ritmo', danger: !enable });
    if (!ok || !ctx.alive()) return;
    try {
      const r = await ctx.api.post(`/admin/api/queues/${q.family}/` + m.mode, { enabled: enable, reason: ok.reason, confirm: m.mode });
      toast(r.changed ? `${fam} ${m.label} ${enable ? 'ATIVADO' : 'DESATIVADO'} · o jogo mostra: ${r.open_modes.length ? r.open_modes.length + ' ritmo(s)' : NONE[q.family]}` : 'Nada mudou (já estava assim) · registrado no Admin Log');
    } catch (e) { if (!ctx.alive() || (e instanceof ApiError && e.kind === 'revoked')) return; toast(e instanceof ApiError ? e.text : 'Falha ao aplicar', 'err'); }
    if (ctx.alive()) ctx.refresh();
  }
  // R128 · LIBERAR TODAS AS LIGAS (teste visual): cenários, tabuleiros e peças de todas as ligas para TODOS os jogadores.
  async function toggleLeagues(lg) {
    const enable = !lg.enabled;
    const ok = await confirmAction({ title: enable ? 'Liberar todas as ligas' : 'Voltar ao normal (liga conquistada)',
      body: enable ? 'Todos os jogadores passam a ver e usar os cenários, tabuleiros e peças de TODAS as ligas (Ferro ao Challenger), na hora, sem nova versão. Só aparência: PL, liga e Ranked não mudam. Fundador e Club continuam exclusivos.'
        : 'Cada jogador volta a ter só os visuais da maior liga que conquistou no Ranked. Quem estava usando um visual não conquistado volta para a Madeira.',
      confirmWord: 'ligas', actionLabel: enable ? 'Liberar ligas' : 'Voltar ao normal', danger: !enable });
    if (!ok || !ctx.alive()) return;
    try {
      const r = await ctx.api.post('/admin/api/leagues-preview', { enabled: enable, reason: ok.reason, confirm: ok.confirm });
      toast(r.changed ? (enable ? 'TODAS AS LIGAS LIBERADAS para todos · o jogo aplica na hora · registrado no Admin Log' : 'Ligas de volta ao normal · registrado no Admin Log') : 'Nada mudou (já estava assim) · registrado no Admin Log');
    } catch (e) { if (!ctx.alive() || (e instanceof ApiError && e.kind === 'revoked')) return; toast(e instanceof ApiError ? e.text : 'Falha ao aplicar', 'err'); }
    if (ctx.alive()) ctx.refresh();
  }
  const leaguesPanel = lg => lg ? h('div', { class: 'qcard' + (lg.enabled ? '' : ' off'), dataset: { family: 'leagues' }, style: 'margin-top:16px' },
    h('div', { class: 'qhead' }, h('span', { class: 't' }, 'Ligas · teste visual'), h('span', { class: 'badge ' + (lg.enabled ? 'on' : 'off') }, lg.enabled ? 'TODAS LIBERADAS' : 'NORMAL')),
    h('p', { class: 'dim', style: 'font-size:13px;margin:8px 0' }, lg.enabled ? 'Todos os jogadores estão com os cenários, tabuleiros e peças de todas as ligas.' : 'Cada jogador tem só os visuais da liga que conquistou no Ranked.',
      ' Só aparência: PL, liga e Ranked não mudam. Fundador e Club continuam exclusivos.'),
    h('div', { class: 'qfoot' },
      h('span', { class: 'dim', style: 'font-size:12px' }, lg.changed_at ? `${lg.enabled ? 'liberado' : 'normal'} por ${lg.changed_by ? lg.changed_by.name : '?'} · ${fmtAgo(lg.changed_at)}` : (lg.enabled ? 'ligado pelo padrão do servidor (FRAIHA_LEAGUES_PREVIEW)' : 'sem alterações desde o início do servidor')),
      canWrite ? h('button', { class: 'btn ' + (lg.enabled ? 'danger' : 'ok'), onclick: () => toggleLeagues(lg), dataset: { action: 'leagues-toggle' } }, lg.enabled ? 'Voltar ao normal' : 'Liberar todas as ligas')
        : h('button', { class: 'btn', disabled: true, title: 'Seu papel é só leitura' }, 'Somente leitura')),
    h('div', { class: 'dim', style: 'font-size:11px;margin-top:6px' }, 'Ao reiniciar o servidor volta para ', lg.boot_default === 'FRAIHA_LEAGUES_PREVIEW' ? 'LIBERADO (variável FRAIHA_LEAGUES_PREVIEW no Render).' : 'NORMAL (para manter liberado após reinício: FRAIHA_LEAGUES_PREVIEW=1 no Render).')) : '';
  const modeStats = m => [m.waiting ? `${m.waiting} na fila` : 'fila vazia', m.longest_wait_ms !== null && m.longest_wait_ms !== undefined ? `maior ${fmtDur(m.longest_wait_ms)}` : '',
    m.avg_wait_ms !== null && m.avg_wait_ms !== undefined ? `média ${fmtDur(m.avg_wait_ms)}` : '', `${m.active_matches || 0} partida(s)`, `${m.active_players || 0} jogando`].filter(Boolean).join(' · ');
  const modeRows = q => h('div', { class: 'modes' },
    h('div', { class: 'dim', style: 'font-size:12px;margin:10px 0 6px' }, 'Ritmos (o jogo mostra só os abertos)', q.enabled ? '' : ` — ${FAMILY_LABEL[q.family]} inteiro DESATIVADO acima`),
    q.modes.map(m => h('div', { class: 'moderow', dataset: { mode: m.mode, open: String(m.open) } },
      h('span', {}, h('b', {}, m.label), h('span', { class: 'dim' }, ` ${m.minutes} min`)),
      h('span', { class: 'dim modestats' }, modeStats(m)),
      h('span', { class: 'badge ' + (m.enabled ? 'on' : 'off') }, m.enabled ? 'ON' : 'OFF'),
      canWrite ? h('button', { class: 'btn sm ' + (m.enabled ? 'danger' : 'ok'), dataset: { action: 'mode-toggle' }, onclick: () => toggleMode(q, m) }, m.enabled ? 'Desativar' : 'Ativar') : '')),
    h('div', { class: 'dim', style: 'font-size:11px;margin-top:6px' }, `Ao reiniciar o servidor: ${q.boot_default === 'todos abertos' ? 'todos abertos' : 'padrão de ' + q.boot_default}.`));
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/queues');
      if (!ctx.alive()) return;
      f.show(
        h('div', { class: 'banner info' }, d.rule, ' ', d.persistent ? '' : 'O estado fica na memória do servidor: um reinício volta tudo para ATIVO.'),
        h('div', { class: 'qgrid' }, d.queues.map(q => h('div', { class: 'qcard' + (q.enabled ? '' : ' off'), dataset: { family: q.family } },
          h('div', { class: 'qhead' }, h('span', { class: 't' }, FAMILY_LABEL[q.family]), pill(q.enabled)),
          h('div', { class: 'kv' },
            h('span', { class: 'k' }, 'Jogadores na fila'), h('span', { class: 'v' }, q.has_queue ? fmtInt(q.waiting.value) : h('span', { class: 'dim' }, 'sem fila (convite)')),
            h('span', { class: 'k' }, 'Maior espera atual'), h('span', { class: 'v' }, q.has_queue ? fmtDur(q.longest_wait_ms.value) : '—'),
            h('span', { class: 'k' }, 'Tempo médio (1 h)'), h('span', { class: 'v' }, q.avg_wait_ms.status === 'unavailable' ? h('span', { class: 'dim', title: q.avg_wait_ms.note }, '—') : [fmtDur(q.avg_wait_ms.value), ' ', statusBadge(q.avg_wait_ms.status)]),
            h('span', { class: 'k' }, 'Partidas ativas'), h('span', { class: 'v' }, fmtInt(q.active_matches.value)),
            h('span', { class: 'k' }, 'Jogadores ativos no modo'), h('span', { class: 'v' }, fmtInt(q.active_players.value))),
          q.modes ? modeRows(q) : q.by_mode.length ? h('p', { class: 'dim', style: 'margin:10px 0 0;font-size:12px' }, q.by_mode.map(m => `${m.mode}: ${m.waiting}`).join(' · ')) : '',
          h('div', { class: 'qfoot' },
            h('span', { class: 'dim', style: 'font-size:12px' }, q.changed_at ? `${q.enabled ? 'ativado' : 'desativado'} por ${q.changed_by ? q.changed_by.name : '?'} · ${fmtAgo(q.changed_at)}` : 'sem alterações desde o início do servidor'),
            canWrite ? h('button', { class: 'btn ' + (q.enabled ? 'danger' : 'ok'), onclick: () => toggle(q), dataset: { action: 'toggle' } }, q.enabled ? 'Desativar fila' : 'Ativar fila')
              : h('button', { class: 'btn', disabled: true, title: 'Seu papel é só leitura' }, 'Somente leitura'))))),
        leaguesPanel(d.leagues),
        h('div', { class: 'panel' }, h('h2', {}, 'Futuro (arquitetura preparada)'),
          h('p', { class: 'muted' }, 'Agendar ativação/desativação, eventos, horários especiais e modo manutenção: ', unavailable())));
    },
  };
}

// ---------------------------------------------------------------- PARTIDAS
export function matches(ctx) {
  const f = frame(ctx, 'Partidas', 'Somente observação: nenhuma intervenção em partida nesta versão.');
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/matches');
      if (!ctx.alive()) return;
      const rows = d.active.map(m => h('tr', {},
        h('td', { class: 'mono' }, m.id.slice(0, 8)), h('td', {}, FAMILY_LABEL[m.family], h('span', { class: 'dim' }, ' · ' + m.mode)),
        h('td', {}, m.players.map((p, i) => h('div', {}, p.bot ? h('span', { class: 'dim' }, 'bot · ' + p.nickname) : p.uid.startsWith('guest:') ? h('span', {}, p.nickname) : h('a', { href: '#/players/' + p.uid }, p.nickname), p.uid && p.uid.startsWith('guest:') ? h('span', { class: 'dim' }, ' (convidado)') : '', p.uid && !p.connected ? h('span', { class: 'badge off', style: 'margin-left:6px' }, 'desconectado') : '', p.voice ? h('span', { class: 'badge blue', style: 'margin-left:6px' }, 'voz') : ''))),
        h('td', {}, fmtDate(m.started_at)), h('td', {}, fmtDur(m.duration_ms)), h('td', {}, m.status === 'starting' ? 'começando' : 'em andamento'),
        h('td', { class: 'dim' }, 'plataforma: —')));
      f.show(
        h('div', { class: 'panel' }, h('h2', {}, `Partidas ativas (${d.active.length})`),
          d.active.length ? h('div', { class: 'tablewrap' }, h('table', {}, h('thead', {}, h('tr', {}, ['Match ID', 'Modo', 'Jogadores', 'Início', 'Duração', 'Status', 'Plataforma'].map(t => h('th', {}, t)))), h('tbody', {}, rows)))
            : stateBox('empty', 'Nenhuma partida em andamento agora.')),
        h('div', { class: 'panel' }, h('h2', {}, 'Recentes (terminadas)'), h('p', { class: 'muted' }, d.recent_finished.note)));
    },
  };
}

// ---------------------------------------------------------------- JOGADORES
export function players(ctx) {
  if (ctx.arg) return player(ctx);
  let q = '';
  const input = h('input', { type: 'search', placeholder: 'Buscar por nickname ou UUID', value: q, maxlength: 40 });
  const f = frame(ctx, 'Jogadores', 'Dados pessoais mínimos. E-mail não é exibido nem pesquisável nesta versão.');
  const form = h('form', { class: 'search', onsubmit: e => { e.preventDefault(); q = input.value.trim(); ctx.refresh(); } }, input, h('button', { class: 'btn primary' }, 'Buscar'));
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/players?q=' + encodeURIComponent(q));
      if (!ctx.alive()) return;
      const rows = d.items.map(p => h('tr', { class: 'click', onclick: () => { location.hash = '#/players/' + p.user_id; } },
        h('td', {}, h('b', {}, p.nickname), h('div', { class: 'mono dim' }, p.user_id.slice(0, 8) + '…')),
        h('td', {}, h('span', { class: 'badge ' + (p.where.place === 'offline' ? 'unavailable' : 'on') }, PLACE_LABEL[p.where.place])),
        h('td', {}, p.where.place === 'match' || p.where.place === 'queue' ? `${FAMILY_LABEL[p.where.family]} · ${p.where.mode}` : '—'),
        h('td', {}, fmtDate(p.created_at)), h('td', {}, fmtAgo(p.last_login_at)), h('td', { class: 'dim' }, '—'),
        h('td', {}, h('span', { class: 'badge ' + (p.club === 'ATIVO' ? 'gold' : p.club === 'INDISPONÍVEL' ? 'off' : 'unavailable'), dataset: { club: p.club } }, p.club)),
        h('td', { dataset: { founder: String(p.founder) } }, p.founder === null ? h('span', { class: 'badge off' }, 'INDISPONÍVEL') : p.founder ? h('span', { class: 'badge gold' }, 'FOUNDER') : '—')));
      f.show(form,
        d.entitlements_read && d.entitlements_read !== 'ok' ? h('div', { class: 'banner err' }, `Clube/Founder: ERRO DE CONSULTA${d.entitlements_read === 'timeout' ? ' (tempo esgotado)' : ''} — status mostrado como INDISPONÍVEL, não como "não possui".`) : '',
        h('div', { class: 'panel' }, d.items.length ? h('div', { class: 'tablewrap' }, h('table', {}, h('thead', {}, h('tr', {}, ['Jogador', 'Status', 'Local atual', 'Cadastro', 'Último login', 'Plataforma', 'Clube', 'Founder'].map(t => h('th', {}, t)))), h('tbody', {}, rows)))
          : stateBox('empty', q ? `Nenhum jogador encontrado para "${q}".` : 'Nenhum jogador cadastrado.')),
        h('p', { class: 'dim' }, 'Elo/liga e partidas por jogador ficam no perfil (um jogador por vez). Plataforma: ', unavailable('PRECISA INSTRUMENTAÇÃO'), ' · Busca por e-mail: ', unavailable(d.email_search.note)));
      input.focus();
    },
  };
}

const LEAGUES = ['Madeira', 'Ferro', 'Bronze', 'Prata', 'Ouro', 'Platina', 'Esmeralda', 'Diamante', 'Mestre', 'Grão-Mestre', 'Challenger'];
const MODE_NAME = { ranked_3min: 'Relâmpago 3 min', ranked_5min: 'Rápida 5 min', ranked_10min: 'Normal 10 min', ranked_20min: 'Convencional 20 min' };
function player(ctx) {
  const f = frame(ctx, 'Perfil do jogador', 'Visão administrativa. Clube/Fundador: alteração só pelo servidor, com confirmação e Admin Log.');
  return {
    error: f.error,
    async load() {
      let d;
      try { d = await ctx.api.get('/admin/api/players/' + encodeURIComponent(ctx.arg)); }
      catch (e) { if (e instanceof ApiError && e.status === 404) return f.show(stateBox('empty', 'Jogador não encontrado.'), h('a', { href: '#/players' }, '← voltar')); throw e; }
      if (!ctx.alive()) return;
      const p = d.profile, w = d.where;
      const ranked = d.ranked && d.ranked.ok ? Object.entries(d.ranked.value || {}).filter(([k]) => MODE_NAME[k]) : [];
      const modes = d.modes && d.modes.ok ? Object.entries(d.modes.value || {}) : [];
      const readErr = sec => stateBox('error', 'ERRO DE CONSULTA' + (sec && sec.error === 'timeout' ? ' (tempo esgotado)' : '') + ' — dado indisponível agora.');
      const entErr = d.entitlements_read && d.entitlements_read !== 'ok';
      f.show(
        h('a', { href: '#/players' }, '← Jogadores'),
        h('div', { class: 'profile-head', style: 'margin-top:12px' }, h('div', { class: 'avatar' }, (p.nickname || '?').slice(0, 1).toUpperCase()),
          h('div', {}, h('h1', {}, p.nickname), h('div', { class: 'mono dim' }, p.user_id)),
          h('div', { class: 'spacer', style: 'flex:1' }),
          h('span', { class: 'badge ' + (w.place === 'offline' ? 'unavailable' : 'on') }, PLACE_LABEL[w.place] + (w.family ? ` · ${FAMILY_LABEL[w.family]} ${w.mode}` : '') + (w.voice ? ' · voz' : ''))),
        entErr ? h('div', { class: 'banner err', id: 'ent-error' }, `Clube/Founder: ${d.club.read_error}. O status real deste jogador é DESCONHECIDO agora (não significa "não possui").`) : '',
        h('div', { class: 'cols3' },
          h('div', { class: 'panel' }, h('h2', {}, 'Dados básicos'), h('div', { class: 'kv' },
            h('span', { class: 'k' }, 'Cadastro'), h('span', { class: 'v' }, fmtDate(p.created_at)),
            h('span', { class: 'k' }, 'Último login'), h('span', { class: 'v' }, fmtDate(p.last_login_at)),
            h('span', { class: 'k' }, 'Conta'), h('span', { class: 'v' }, p.account_status || '—'),
            h('span', { class: 'k' }, 'Plataforma'), h('span', { class: 'v' }, unavailable('PRECISA INSTRUMENTAÇÃO')),
            h('span', { class: 'k' }, 'Partida atual'), h('span', { class: 'v mono' }, w.match_id ? w.match_id.slice(0, 8) : '—'),
            h('span', { class: 'k' }, 'Fila atual'), h('span', { class: 'v' }, w.place === 'queue' ? `${w.mode} · ${fmtDur(w.wait_ms)}` : '—')),
            modBlock(ctx, p)),
          h('div', { class: 'panel' }, h('h2', {}, 'Clube FRAIHA e Fundador'), h('div', { class: 'kv' },
            h('span', { class: 'k' }, 'Status'), h('span', { class: 'v' }, h('span', { class: 'badge ' + (d.club.status === 'ATIVO' ? 'gold' : entErr ? 'off' : 'unavailable'), id: 'club-status' }, d.club.status)),
            h('span', { class: 'k' }, 'Plano'), h('span', { class: 'v dim' }, d.club.plan.note),
            h('span', { class: 'k' }, 'Origem'), h('span', { class: 'v' }, entErr ? h('span', { class: 'unav' }, 'INDISPONÍVEL') : d.club.source.value || h('span', { class: 'dim' }, '—')),
            h('span', { class: 'k' }, 'Início'), h('span', { class: 'v dim' }, 'migration necessária'),
            h('span', { class: 'k' }, 'Expiração'), h('span', { class: 'v' }, entErr ? h('span', { class: 'unav' }, 'INDISPONÍVEL') : d.club.expires_at.value ? fmtDate(d.club.expires_at.value) : '—'),
            h('span', { class: 'k' }, 'Renovação'), h('span', { class: 'v dim' }, 'backend necessário'),
            h('span', { class: 'k' }, 'Observação admin'), h('span', { class: 'v dim' }, 'migration necessária')),
            h('div', { style: 'margin-top:12px' }, entBlock(ctx, { user_id: p.user_id, nickname: p.nickname, ent: d.ent, has_profile: true }))),
          h('div', { class: 'panel' }, h('h2', {}, 'Pacote Fundador'), h('div', { class: 'kv' },
            h('span', { class: 'k' }, 'Founder'), h('span', { class: 'v', id: 'founder-value' }, d.founder.status === 'unavailable' ? h('span', { class: 'badge off' }, 'INDISPONÍVEL') : d.founder.value ? h('span', { class: 'badge gold' }, 'SIM') : 'NÃO'),
            h('span', { class: 'k' }, 'Desde'), h('span', { class: 'v' }, fmtDate(d.founder.since)),
            h('span', { class: 'k' }, 'Edição/nível'), h('span', { class: 'v dim' }, 'ainda não definido'),
            h('span', { class: 'k' }, 'Badge / moldura'), h('span', { class: 'v dim' }, 'futuro')),
            h('p', { class: 'dim', style: 'font-size:12px;margin-top:12px' }, 'Conceder/revogar Fundador: no quadro Clube FRAIHA (os dois benefícios são independentes).'),
            h('p', { class: 'dim', style: 'font-size:12px' }, 'INDISPONÍVEL — BACKEND NECESSÁRIO.'))),
        crownsPanel(ctx, p),
        h('div', { class: 'panel' }, h('h2', {}, 'Ranked (por modo)'), ranked.length ? h('div', { class: 'tablewrap' }, h('table', {},
          h('thead', {}, h('tr', {}, ['Modo', 'Liga', 'PL', 'Partidas', 'Vitórias', 'Derrotas', 'Empates', 'Maior liga'].map(t => h('th', {}, t)))),
          h('tbody', {}, ranked.map(([k, s]) => h('tr', {}, h('td', {}, MODE_NAME[k]), h('td', {}, LEAGUES[s.league] || s.league), h('td', {}, fmtInt(s.pl)), h('td', {}, fmtInt(s.matches)), h('td', {}, fmtInt(s.wins)), h('td', {}, fmtInt(s.losses)), h('td', {}, fmtInt(s.draws)), h('td', {}, LEAGUES[s.highest_league] || '—'))))))
          : d.ranked && !d.ranked.ok ? readErr(d.ranked) : stateBox('empty', 'Sem estatísticas de Ranked.'),
          h('p', { class: 'dim', style: 'font-size:12px' }, 'O FRAIHA usa liga + PL por modo (não Elo numérico).')),
        h('div', { class: 'panel' }, h('h2', {}, 'Outros modos'), modes.length ? h('div', { class: 'mini' }, modes.map(([k, s]) => h('div', {}, h('span', { class: 'dim' }, (FAMILY_LABEL[k] || k)), h('b', {}, `${fmtInt(s.wins)} V · ${fmtInt(s.losses)} D`)))) : d.modes && !d.modes.ok ? readErr(d.modes) : stateBox('empty', 'Sem registros.')));
    },
  };
}

// ---------------------------------------------------------------- R168 · COROAS do jogador
const CROWN_REASON = { game: 'Partida', daily: 'Entrada do dia', streak: 'Sequência', mission: 'Missão', buy: 'Compra na Loja', tournament: 'Torneio', admin: 'Admin', pass: 'Passe', creator: 'Criador' };
function crownsPanel(ctx, p) {
  const bal = h('b', { id: 'crowns-balance', style: 'font-size:22px' }, '…');
  const list = h('div', { class: 'mini', id: 'crowns-recent' });
  const write = canEnt(ctx);
  let balance = 0;
  const load = async () => {
    try {
      const d = await ctx.api.get(`/admin/api/players/${p.user_id}/crowns`);
      if (!ctx.alive()) return;
      if (!d.available) { bal.textContent = 'INDISPONÍVEL'; return; }
      balance = d.balance || 0;
      bal.textContent = balance.toLocaleString('pt-BR') + ' Coroas';
      list.replaceChildren(...(d.recent || []).filter(r => r.delta !== 0).slice(0, 8).map(r => h('div', {}, h('span', { class: 'dim' }, (CROWN_REASON[r.reason] || r.reason) + ' · ' + fmtDay(r.at)), h('b', { style: 'color:' + (r.delta > 0 ? '#7fd99a' : '#ff8a7a') }, (r.delta > 0 ? '+' : '') + r.delta.toLocaleString('pt-BR')))));
    } catch (e) { if (ctx.alive()) bal.textContent = 'ERRO DE CONSULTA'; }
  };
  const act = async take => {
    const ok = await crownsDialog({ playerName: p.nickname || p.user_id.slice(0, 8), balance, take });
    if (!ok || !ctx.alive()) return;
    try {
      const r = await ctx.api.post(`/admin/api/players/${p.user_id}/crowns`, ok);
      toast(`${ok.amount > 0 ? 'Enviadas' : 'Retiradas'} ${Math.abs(ok.amount).toLocaleString('pt-BR')} Coroas · saldo ${Number(r.balance).toLocaleString('pt-BR')} · registrado no Admin Log`);
    } catch (e) { if (!ctx.alive() || (e instanceof ApiError && e.kind === 'revoked')) return; toast(e instanceof ApiError ? e.text : 'Falha ao enviar', 'err'); }
    load();
  };
  load();
  return h('div', { class: 'panel', id: 'crowns-panel' }, h('h2', {}, 'Coroas'),
    h('div', { style: 'display:flex;align-items:center;gap:12px;flex-wrap:wrap' }, h('span', { class: 'dim' }, 'Saldo'), bal,
      write ? h('button', { class: 'btn sm ok', id: 'crowns-give', onclick: () => act(false) }, 'ENVIAR COROAS') : '',
      write ? h('button', { class: 'btn sm danger', id: 'crowns-take', onclick: () => act(true) }, 'TIRAR') : ''),
    h('p', { class: 'dim', style: 'font-size:12px' }, 'O jogador online recebe o aviso na hora. Tudo fica no Admin Log.'),
    list);
}

// ---------------------------------------------------------------- CLUBE / FUNDADOR
// Estado e ações vêm SEMPRE do servidor (p.ent = { version, club:{status,expires_at,…}, founder:{value,since} }).
// O botão só aparece para quem tem 'entitlements.write' (owner); o servidor confere de novo em cada pedido.
const fmtDay = iso => { const d = new Date(iso); return isNaN(d) ? '—' : d.toLocaleDateString('pt-BR'); };
const CLUB_BADGE = st => st === 'ATIVO' ? 'gold' : st === 'EXPIRADO' ? 'off' : 'unavailable';
const canEnt = ctx => !!(ctx.session && ctx.session.admin.perms.includes('entitlements.write'));
const ENT_DONE = { club: { grant: 'Clube CONCEDIDO', change: 'Clube ALTERADO', revoke: 'Clube REVOGADO' }, founder: { grant: 'Fundador CONCEDIDO', revoke: 'Fundador REVOGADO' } };
async function doEnt(ctx, p, kind, action) {
  const ok = await entitlementDialog({ kind, action, playerName: p.nickname || p.user_id.slice(0, 8) });
  if (!ok || !ctx.alive()) return;   // cancelado ou sessão encerrada: nada é enviado
  try {
    const r = await ctx.api.post(`/admin/api/players/${p.user_id}/${kind}`, { action, ...ok, confirm: p.user_id, expect_version: p.ent.version });
    toast(r.changed ? `${ENT_DONE[kind][action]} pelo servidor · registrado no Admin Log` : 'Nada mudou (já estava assim) · registrado no Admin Log');
  } catch (e) { if (!ctx.alive() || (e instanceof ApiError && e.kind === 'revoked')) return; toast(e instanceof ApiError ? e.text : 'Falha ao aplicar', 'err'); }
  if (ctx.alive()) ctx.refresh();
}
function entBlock(ctx, p) {
  if (!p.ent) return h('div', { class: 'ent' }, h('span', { class: 'badge off' }, 'INDISPONÍVEL'), h('span', { class: 'dim' }, ' erro de consulta — status desconhecido'));
  const write = canEnt(ctx) && p.has_profile !== false;
  const btn = (label, kind, action, cls = '') => write ? h('button', { class: 'btn sm ' + cls, dataset: { act: kind + '.' + action, uid: p.user_id }, onclick: () => doEnt(ctx, p, kind, action) }, label) : '';
  const c = p.ent.club, f = p.ent.founder;
  const clubTxt = c.status === 'ATIVO' ? (c.expires_at ? 'até ' + fmtDay(c.expires_at) : 'sem expiração') : c.status === 'EXPIRADO' && c.expires_at ? 'em ' + fmtDay(c.expires_at) : '';
  return h('div', { class: 'ent' },
    h('div', { class: 'entline', dataset: { club: c.status } }, h('span', { class: 'dim' }, 'Clube'), h('span', { class: 'badge ' + CLUB_BADGE(c.status) }, c.status), clubTxt ? h('span', { class: 'dim' }, clubTxt) : '',
      ...(c.active ? [btn('ALTERAR', 'club', 'change'), btn('REVOGAR', 'club', 'revoke', 'danger')] : [btn('CONCEDER', 'club', 'grant', 'ok')])),
    h('div', { class: 'entline', dataset: { founder: String(f.value) } }, h('span', { class: 'dim' }, 'Fundador'), h('span', { class: 'badge ' + (f.value ? 'gold' : 'unavailable') }, f.value ? 'SIM' : 'NÃO'),
      f.value && f.since ? h('span', { class: 'dim' }, 'desde ' + fmtDay(f.since)) : '',
      f.value ? btn('REVOGAR', 'founder', 'revoke', 'danger') : btn('CONCEDER', 'founder', 'grant', 'ok')),
    p.has_profile === false ? h('div', { class: 'dim' }, 'sem perfil ainda (escolhendo nome): benefícios só depois') : '');
}
const avatarOf = p => p.avatar_url ? h('img', { class: 'av', src: p.avatar_url, alt: '' }) : h('span', { class: 'av' }, (p.nickname || '?').slice(0, 1).toUpperCase());
function onlinePanel(ctx, d) {
  return h('div', { class: 'panel', id: 'online-panel' },
    h('h2', {}, 'Jogadores online agora ', h('span', { class: 'badge real' }, `${d.items.length} conta${d.items.length === 1 ? '' : 's'}`), d.guests ? h('span', { class: 'dim', style: 'font-size:12px' }, ` + ${d.guests} convidado(s)`) : ''),
    d.entitlements_read !== 'ok' ? h('div', { class: 'banner err' }, 'ERRO DE CONSULTA de Clube/Fundador: status mostrado como INDISPONÍVEL (não significa "não possui").') : '',
    d.items.length ? h('div', { class: 'onlist' }, d.items.map(p => h('div', { class: 'onrow', dataset: { uid: p.user_id } },
      h('div', { class: 'who2' }, avatarOf(p), h('div', {}, h('a', { href: '#/players/' + p.user_id }, h('b', {}, p.nickname || '(sem nome)')), h('div', { class: 'mono dim' }, p.user_id.slice(0, 8) + '…')),
        h('span', { class: 'badge on' }, p.where.place === 'match' ? 'EM PARTIDA' : p.where.place === 'queue' ? 'EM FILA' : 'ONLINE')),
      entBlock(ctx, p))))
      : stateBox('empty', 'Nenhuma conta online agora.'),
    d.truncated ? h('p', { class: 'dim' }, 'Mostrando as primeiras 200 contas.') : '');
}
function entitlementView(ctx, kind) {
  const isClub = kind === 'club';
  const f = frame(ctx, isClub ? 'Clube FRAIHA' : 'Fundador', isClub ? 'Conceder, alterar e revogar o Clube. Aplicado e validado no SERVIDOR; registrado no Admin Log.' : 'Conceder e revogar Fundador (permanente, sem validade). Independente do Clube.');
  return {
    error: f.error,
    async load() {
      const [on, d] = await Promise.all([ctx.api.get('/admin/api/online'), ctx.api.get('/admin/api/players?q=')]);
      if (!ctx.alive()) return;
      const list = d.items.filter(p => isClub ? (p.club === 'ATIVO' || p.club === 'EXPIRADO') : p.founder === true);
      f.show(
        canEnt(ctx) ? '' : h('div', { class: 'banner info' }, 'Somente leitura: só o papel owner altera Clube/Fundador.'),
        onlinePanel(ctx, on),
        h('div', { class: 'panel' }, h('h2', {}, isClub ? 'Com Clube (amostra)' : 'Fundadores (amostra)', ' ', statusBadge('partial')),
          h('p', { class: 'dim', style: 'font-size:12px;margin-top:-6px' }, 'Entre os 50 jogadores com login mais recente. Para alterar alguém offline, abra o perfil.'),
          d.entitlements_read && d.entitlements_read !== 'ok' ? h('div', { class: 'banner err' }, 'ERRO DE CONSULTA: a lista pode estar incompleta.') : '',
          list.length ? h('table', {}, h('thead', {}, h('tr', {}, ['Jogador', isClub ? 'Clube' : 'Fundador', 'Último login'].map(t => h('th', {}, t)))),
            h('tbody', {}, list.map(p => h('tr', { class: 'click', onclick: () => { location.hash = '#/players/' + p.user_id; } }, h('td', {}, p.nickname), h('td', {}, h('span', { class: 'badge ' + (isClub ? CLUB_BADGE(p.club) : 'gold') }, isClub ? p.club : 'SIM')), h('td', {}, fmtAgo(p.last_login_at))))))
            : stateBox('empty', 'Nenhum encontrado na amostra.')),
        h('p', { class: 'dim' }, 'Admin Log em memória do servidor + linha "[admin-audit]" no log do Render (tabela durável = migration proposta 0011, não aplicada).'));
    },
  };
}
export const club = ctx => entitlementView(ctx, 'club');
export const founder = ctx => entitlementView(ctx, 'founder');

// ---------------------------------------------------------------- R103 · VENDAS
const BRL = c => (Number(c || 0) / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const PAY_ST = { paid: ['PAGO', 'on'], pending: ['PENDENTE', 'partial'], refunded: ['REEMBOLSADO', 'off'], cancelled: ['CANCELADO', 'off'], failed: ['FALHOU', 'off'], sold_out: ['PAGO SEM VAGA · REEMBOLSAR', 'warn'] };
export function sales(ctx) {
  const f = frame(ctx, 'Vendas', 'Pagamentos do Mercado Pago (PIX e cartão). Reembolso: faça no painel do Mercado Pago — o jogo retira a vantagem sozinho quando o aviso chega.');
  let filter = '';
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/payments' + (filter ? '?status=' + filter : ''));
      if (!ctx.alive()) return;
      if (!d.available) return f.show(stateBox('error', 'Pagamentos indisponíveis neste servidor (sem banco ou sem a tabela payments).'));
      const s = d.summary, can = ctx.session && ctx.session.admin && (ctx.session.admin.perms || []).includes('payments.write');
      const prod = Object.entries(s.by_product).map(([k, v]) => `${k}: ${v}`).join(' · ') || '—';
      const chips = [['', 'Todos'], ['paid', 'Pagos'], ['pending', 'Pendentes'], ['refunded', 'Reembolsados'], ['sold_out', 'Sem vaga (reembolsar)']].map(([k, t]) =>
        h('button', { class: 'btn' + (filter === k ? ' primary' : ''), onclick: () => { filter = k; ctx.refresh(); } }, t));
      f.show(
        h('div', { class: 'cards' },
          card('Vendido no mês', { value: s.paid_month_cents, status: 'real', note: `${fmtInt(s.paid_month)} pagamento(s) desde o dia 1º` }, { fmt: BRL, hero: true }),
          card('Vendido no total', { value: s.paid_total_cents, status: 'real', note: `${fmtInt(s.paid_total)} pagamento(s) · ${prod}` }, { fmt: BRL }),
          card('Pendentes', { value: fmtInt(s.pending), status: 'real', note: 'PIX gerado e ainda não pago' }),
          card('Reembolsados', { value: fmtInt(s.refunded), status: 'real', note: 'vantagem retirada automaticamente' }),
          card('Sem vaga · reembolsar', { value: fmtInt(s.sold_out || 0), status: 'real', note: s.sold_out ? '⚠ Fundador pago depois das vagas acabarem: nada foi entregue, devolva o valor no Mercado Pago' : 'Fundador pago depois das vagas acabarem (nada foi entregue)' })),
        h('div', { class: 'panel' },
          h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:10px' }, ...chips,
            can ? h('button', { class: 'btn', style: 'margin-left:auto', onclick: async () => {
              const ok = await confirmAction({ title: 'Conferir entregas', body: 'Entrega agora a vantagem de todo pagamento aprovado que ainda não liberou nada.', confirmWord: 'CONFERIR', actionLabel: 'Conferir', danger: false });
              if (!ok) return;
              const r = await ctx.api.post('/admin/api/payments/reconcile', {}); toast(r.result && r.result.missing ? 'Banco sem a migração 0012.' : `Entregues: ${(r.result && r.result.granted) || 0}`); ctx.refresh(); } }, 'Conferir entregas') : ''),
          d.items.length ? h('div', { class: 'tablewrap' }, h('table', {}, h('thead', {}, h('tr', {}, ['Quando', 'Jogador', 'Produto', 'Forma', 'Valor', 'Situação', 'Pedido'].map(t => h('th', {}, t)))),
            h('tbody', {}, d.items.map(r => h('tr', { class: 'click', onclick: () => { location.hash = '#/players/' + r.user_id; } },
              h('td', {}, fmtDate(r.paid_at || r.created_at)), h('td', {}, r.nickname || r.user_id.slice(0, 8)), h('td', {}, r.title),
              h('td', {}, r.method === 'pix' ? 'PIX' : 'Cartão'), h('td', {}, BRL(r.amount_cents)),
              h('td', {}, h('span', { class: 'badge ' + (PAY_ST[r.status] || ['', ''])[1] }, (PAY_ST[r.status] || [r.status])[0])),
              h('td', { class: 'mono dim' }, String(r.provider_ref || '').slice(0, 8)))))))
            : stateBox('empty', 'Nenhum pagamento ainda.')));
    },
  };
}

// ---------------------------------------------------------------- R121 · CRIADORES (Apoie um Criador)
const SALE_ST = { due: ['A pagar', 'warn'], paid: ['Paga', 'on'], cancelled: ['Cancelada (reembolso)', 'off'], refunded_after_paid: ['Reembolsada depois de paga', 'off'] };
function creatorDialog(c) {
  return new Promise(resolve => {
    const f = (label, el) => h('label', {}, label, el);
    const code = h('input', { type: 'text', value: c ? c.code : '', placeholder: 'XADREZDOJOAO', maxlength: 20, disabled: !!c, style: 'text-transform:uppercase' });
    const name = h('input', { type: 'text', value: c ? c.name : '', placeholder: 'Nome do criador', maxlength: 60 });
    const pct = h('input', { type: 'number', min: 0, max: 50, value: c ? c.pct : 10 });
    const gift = h('input', { type: 'number', min: 0, max: 5000, value: c ? c.gift_crowns : 200 });
    const contact = h('input', { type: 'text', value: c ? c.contact : '', placeholder: 'Instagram / PIX / e-mail', maxlength: 120 });
    const active = h('input', { type: 'checkbox', checked: c ? c.active : true });
    const reason = h('textarea', { rows: 2, placeholder: 'Ex.: parceria fechada por WhatsApp', maxlength: 300 });
    const close = v => { bg.remove(); resolve(v); };
    const bg = h('div', { class: 'modal-bg', onclick: e => { if (e.target === bg) close(null); } },
      h('div', { class: 'modal', role: 'dialog', 'aria-modal': 'true' },
        h('h3', {}, c ? 'Editar criador ' + c.code : 'Novo criador'),
        h('div', { class: 'fields' }, f('Código (3 a 20 letras/números)', code), f('Nome', name), f('Comissão (% de cada compra)', pct),
          f('Presente para quem usa o código pela 1ª vez (Coroas)', gift), f('Contato', contact), h('label', { style: 'display:flex;gap:8px;align-items:center' }, active, 'Ativo'),
          f('Motivo (vai para o Admin Log)', reason)),
        h('div', { class: 'actions' }, h('button', { class: 'btn ghost', onclick: () => close(null) }, 'Cancelar'),
          h('button', { class: 'btn ok', onclick: () => close({ code: code.value.trim().toUpperCase(), name: name.value.trim(), pct: Number(pct.value), gift_crowns: Number(gift.value), contact: contact.value.trim(), active: active.checked, reason: reason.value.trim() }) }, 'Salvar'))));
    document.body.append(bg); (c ? name : code).focus();
  });
}
export function creators(ctx) {
  const f = frame(ctx, 'Criadores', 'Apoie um Criador: o jogador usa o código do criador (vale 30 dias, renova ao digitar de novo). Cada compra paga nesse período gera a comissão do criador. Pague por fora (PIX) e marque como paga aqui.');
  const can = () => ctx.session && ctx.session.admin && (ctx.session.admin.perms || []).includes('payments.write');
  const save = async c => {
    const v = await creatorDialog(c);
    if (!v) return;
    try { await ctx.api.post('/admin/api/creators', v); toast('Criador salvo.'); }
    catch (e) { toast({ invalid_code: 'Código inválido (3 a 20 letras/números).', invalid_name: 'Informe o nome.', invalid_values: 'Comissão de 0 a 50% e presente de 0 a 5.000.' }[e && e.code] || 'Não foi possível salvar.'); }
    ctx.refresh();
  };
  const pay = async c => {
    const ok = await confirmAction({ title: 'Marcar comissão de ' + c.name + ' como paga', body: `${BRL(c.due_cents)} em comissões a pagar. Faça o PIX para o criador e depois confirme aqui.`, confirmWord: 'PAGO', actionLabel: 'Marcar como paga', danger: false });
    if (!ok) return;
    const r = await ctx.api.post('/admin/api/creators/' + c.code + '/pay', { reason: ok.reason });
    toast(`${r.paid} venda(s) marcadas como pagas (${BRL(r.commission_cents)}).`); ctx.refresh();
  };
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/creators');
      if (!ctx.alive()) return;
      if (!d.available) return f.show(stateBox('error', d.error === 'migration_0019_missing' ? 'Banco sem a migração 0019 (criadores).' : 'Criadores indisponíveis neste servidor.'));
      const tot = k => d.items.reduce((a, c) => a + (c[k] || 0), 0);
      const item = c => h('div', { class: 'panel' },
        h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;align-items:center' },
          h('strong', {}, c.name), h('span', { class: 'badge' }, c.code), pill(c.active), h('span', { class: 'dim' }, `${c.pct}% · presente ${fmtInt(c.gift_crowns)} Coroas`),
          c.contact ? h('span', { class: 'dim' }, c.contact) : '',
          can() ? h('span', { style: 'margin-left:auto;display:flex;gap:8px' },
            h('button', { class: 'btn', onclick: () => save(c) }, 'Editar'),
            c.due_cents > 0 ? h('button', { class: 'btn ok', onclick: () => pay(c) }, 'Marcar como paga') : '') : ''),
        h('div', { class: 'cards', style: 'margin-top:10px' },
          card('Jogadores que usaram', { value: fmtInt(c.players), status: 'real', note: `${fmtInt(c.active_players)} apoiando agora` }),
          card('Vendas', { value: fmtInt(c.sales), status: 'real', note: BRL(c.sold_cents) + ' vendidos' }),
          card('A pagar', { value: c.due_cents, status: 'real', note: 'comissão ainda não paga' }, { fmt: BRL, hero: c.due_cents > 0 }),
          card('Já pago', { value: c.paid_cents, status: 'real', note: c.clawback_cents ? `${BRL(c.clawback_cents)} de compras reembolsadas depois de pagas` : 'total pago ao criador' }, { fmt: BRL })),
        c.recent.length ? h('div', { class: 'tablewrap' }, h('table', {}, h('thead', {}, h('tr', {}, ['Quando', 'Produto', 'Valor', 'Comissão', 'Situação'].map(t => h('th', {}, t)))),
          h('tbody', {}, c.recent.map(r => h('tr', {}, h('td', {}, fmtDate(r.created_at)), h('td', {}, r.product_id), h('td', {}, BRL(r.amount_cents)), h('td', {}, BRL(r.commission_cents)),
            h('td', {}, h('span', { class: 'badge ' + (SALE_ST[r.status] || ['', ''])[1] }, (SALE_ST[r.status] || [r.status])[0]))))))) : h('p', { class: 'dim' }, 'Nenhuma venda ainda.'));
      f.show(
        h('div', { class: 'cards' },
          card('Criadores', { value: fmtInt(d.items.length), status: 'real', note: `${fmtInt(d.items.filter(c => c.active).length)} ativos` }),
          card('Comissão a pagar', { value: tot('due_cents'), status: 'real', note: 'soma de todos os criadores' }, { fmt: BRL, hero: true }),
          card('Vendido por criadores', { value: tot('sold_cents'), status: 'real', note: fmtInt(tot('sales')) + ' venda(s)' }, { fmt: BRL })),
        can() ? h('div', { style: 'margin:10px 0' }, h('button', { class: 'btn primary', onclick: () => save(null) }, '+ Novo criador')) : '',
        d.items.length ? h('div', {}, d.items.map(item)) : stateBox('empty', 'Nenhum criador cadastrado ainda.'));
    },
  };
}

// ---------------------------------------------------------------- R104 · DENÚNCIAS
// Suspender / banir / tirar suspensão direto na ficha do jogador.
function modBlock(ctx, p) {
  if (!(ctx.session && ctx.session.admin && (ctx.session.admin.perms || []).includes('moderation.write')) || p.account_status === 'deleted') return '';
  const run = async (path, body, title, word, label, danger, text) => {
    const ok = await confirmAction({ title, body: text, confirmWord: word, actionLabel: label, danger });
    if (!ok) return;
    try { await ctx.api.post('/admin/api/players/' + p.user_id + path, { ...body, reason: ok.reason }); toast('Feito.'); }
    catch (e) { toast(e && e.code === 'migration_0013_missing' ? 'Banco sem a migração 0013.' : 'Não foi possível concluir.'); }
    ctx.refresh();
  };
  if (p.account_status === 'suspended') return h('div', { style: 'margin-top:12px;display:flex;gap:8px' },
    h('button', { class: 'btn ok', onclick: () => run('/unsuspend', {}, 'Tirar suspensão de ' + p.nickname, 'LIBERAR', 'Liberar', false, 'A conta volta a entrar no jogo na hora.') }, 'Tirar suspensão'));
  return h('div', { style: 'margin-top:12px;display:flex;gap:8px;flex-wrap:wrap' },
    ...[[1, '1 dia'], [7, '7 dias'], [30, '30 dias']].map(([d, t]) => h('button', { class: 'btn danger', onclick: () => run('/suspend', { days: d }, 'Suspender ' + p.nickname, 'SUSPENDER', 'Suspender', true, `Sem entrar no jogo por ${t}. É desconectado na hora.`) }, 'Suspender ' + t)),
    h('button', { class: 'btn danger', onclick: () => run('/suspend', { days: null }, 'Banir ' + p.nickname, 'BANIR', 'Banir', true, 'Sem entrar no jogo até alguém tirar a suspensão.') }, 'Banir'));
}
const REP_ST = { open: ['Aberta', 'warn'], dismissed: ['Arquivada', 'off'], actioned: ['Resolvida', 'on'] };
const SUSP = [[1, '1 dia'], [7, '7 dias'], [30, '30 dias'], [null, 'Banir (sem prazo)']];
export function reports(ctx) {
  const f = frame(ctx, 'Denúncias', 'Denúncias feitas no jogo (partida = chat e voz, conversa privada, perfil, CHAT GLOBAL). A voz não é gravada: só há o trecho das mensagens escritas.');
  let filter = 'open';
  const can = () => ctx.session && ctx.session.admin && (ctx.session.admin.perms || []).includes('moderation.write');
  const setStatus = async (r, status) => {
    const ok = await confirmAction({ title: status === 'dismissed' ? 'Arquivar denúncia' : 'Reabrir denúncia', body: `Denúncia contra ${r.reported.nickname}.`, confirmWord: status === 'dismissed' ? 'ARQUIVAR' : 'REABRIR', actionLabel: status === 'dismissed' ? 'Arquivar' : 'Reabrir', danger: false });
    if (!ok) return;
    await ctx.api.post('/admin/api/reports/' + r.report_id, { status, note: ok.reason }); toast('Denúncia atualizada.'); ctx.refresh();
  };
  const suspend = async (r, days, label) => {
    const ok = await confirmAction({ title: (days ? 'Suspender ' : 'Banir ') + r.reported.nickname, body: days ? `A conta fica sem entrar no jogo por ${label}. Ela é desconectada na hora e volta sozinha no fim do prazo.` : 'A conta fica sem entrar no jogo até você tirar a suspensão na tela Jogadores ou aqui.', confirmWord: days ? 'SUSPENDER' : 'BANIR', actionLabel: days ? 'Suspender' : 'Banir', danger: true });
    if (!ok) return;
    try { await ctx.api.post('/admin/api/players/' + r.reported.user_id + '/suspend', { days, reason: ok.reason, report_id: r.report_id }); toast('Conta suspensa.'); }
    catch (e) { toast(e && e.code === 'migration_0013_missing' ? 'Banco sem a migração 0013.' : 'Não foi possível suspender.'); }
    ctx.refresh();
  };
  const unsuspend = async (r) => {
    const ok = await confirmAction({ title: 'Tirar suspensão de ' + r.reported.nickname, body: 'A conta volta a entrar no jogo na hora.', confirmWord: 'LIBERAR', actionLabel: 'Liberar', danger: false });
    if (!ok) return;
    await ctx.api.post('/admin/api/players/' + r.reported.user_id + '/unsuspend', { reason: ok.reason }); toast('Suspensão retirada.'); ctx.refresh();
  };
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/reports?status=' + filter);
      if (!ctx.alive()) return;
      if (!d.available) return f.show(stateBox('error', d.error === 'migration_0013_missing' ? 'Banco sem a migração 0013 (denúncias). Até aplicar, as denúncias ficam só no log do servidor.' : 'Denúncias indisponíveis neste servidor.'));
      const chips = [['open', 'Abertas'], ['actioned', 'Resolvidas'], ['dismissed', 'Arquivadas'], ['', 'Todas']].map(([k, t]) =>
        h('button', { class: 'btn' + (filter === k ? ' primary' : ''), onclick: () => { filter = k; ctx.refresh(); } }, t));
      const item = r => {
        const susp = r.reported.account_status === 'suspended';
        return h('div', { class: 'panel' },
          h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;align-items:center' },
            h('strong', {}, r.reported.nickname), h('span', { class: 'badge ' + (REP_ST[r.status] || ['', ''])[1] }, (REP_ST[r.status] || [r.status])[0]),
            h('span', { class: 'badge' }, r.kind_label), susp ? h('span', { class: 'badge off' }, 'SUSPENSA' + (r.reported.suspended_until ? ' até ' + fmtDate(r.reported.suspended_until) : ' (sem prazo)')) : '',
            r.reports_in_list > 1 ? h('span', { class: 'badge warn' }, `${r.reports_in_list} denúncias nesta lista`) : '',
            h('span', { class: 'dim', style: 'margin-left:auto' }, `por ${r.reporter.nickname} · ${fmtAgo(r.created_at)}`)),
          r.reason ? h('p', { class: 'muted' }, 'Motivo: ' + r.reason) : '',
          r.messages.length ? h('div', { class: 'mono', style: 'white-space:pre-wrap;margin:8px 0;max-height:180px;overflow:auto' }, r.messages.map(t => '• ' + t).join('\n'))
            : h('p', { class: 'dim' }, 'Sem mensagens escritas no trecho (denúncia de voz ou de perfil).'),
          r.note ? h('p', { class: 'dim' }, `Nota: ${r.note} — ${r.handled_by || ''}`) : '',
          can() ? h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap' },
            h('button', { class: 'btn', onclick: () => { location.hash = '#/players/' + r.reported.user_id; } }, 'Ver jogador'),
            ...(susp ? [h('button', { class: 'btn ok', onclick: () => unsuspend(r) }, 'Tirar suspensão')] : SUSP.map(([d, t]) => h('button', { class: 'btn danger', onclick: () => suspend(r, d, t) }, d ? 'Suspender ' + t : t))),
            r.status === 'open' ? h('button', { class: 'btn ghost', onclick: () => setStatus(r, 'dismissed') }, 'Arquivar') : h('button', { class: 'btn ghost', onclick: () => setStatus(r, 'open') }, 'Reabrir')) : '');
      };
      f.show(h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px' }, ...chips),
        d.items.length ? h('div', {}, d.items.map(item)) : stateBox('empty', filter === 'open' ? 'Nenhuma denúncia aberta.' : 'Nada por aqui.'));
    },
  };
}

// ---------------------------------------------------------------- ADMIN LOG
export function audit(ctx) {
  const f = frame(ctx, 'Admin Log', 'Toda ação administrativa real é registrada pelo SERVIDOR antes de responder.');
  const ACT = { 'queue.disable': 'desativou', 'queue.enable': 'ativou', 'queue.mode_disable': 'desativou ritmo', 'queue.mode_enable': 'ativou ritmo', clube_grant: 'concedeu Clube', clube_change: 'alterou Clube', clube_revoke: 'revogou Clube', founder_grant: 'concedeu Fundador', founder_revoke: 'revogou Fundador', crowns_give: 'enviou Coroas', crowns_take: 'tirou Coroas', 'leagues.preview_on': 'liberou todas as ligas', 'leagues.preview_off': 'voltou as ligas ao normal' };
  const st = x => !x ? '—' : 'enabled' in x ? (x.enabled ? 'ativo' : 'desativado') : `Clube ${x.club}${x.club_expires_at ? ' até ' + new Date(x.club_expires_at).toLocaleDateString('pt-BR') : x.club === 'ATIVO' ? ' sem expiração' : ''} · Fundador ${x.founder ? 'SIM' : 'NÃO'}`;
  const tgt = t => !t ? '—' : t.mode ? `${FAMILY_LABEL[t.family]} ${t.mode.replace(/^(ranked|casual)_/, '')}` : t.family ? FAMILY_LABEL[t.family] : t.type === 'leagues' ? 'Ligas (visual, todos)' : t.user_id ? `${t.nickname || '?'} (${t.user_id.slice(0, 8)})` : JSON.stringify(t);
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/audit?limit=200');
      if (!ctx.alive()) return;
      f.show(
        d.persistent ? '' : h('div', { class: 'banner warn' }, 'Persistência: memória do servidor + linha "[admin-audit]" no log do Render. Tabela durável = migration proposta (não aplicada).'),
        h('div', { class: 'panel' }, d.items.length ? h('div', { class: 'tablewrap' }, h('table', {}, h('thead', {}, h('tr', {}, ['Quando', 'Administrador', 'Ação', 'Alvo', 'Antes', 'Depois', 'Resultado', 'Motivo'].map(t => h('th', {}, t)))),
          h('tbody', {}, d.items.map(e => h('tr', {}, h('td', {}, fmtDate(e.at)), h('td', {}, e.actor ? e.actor.name : '—', h('div', { class: 'dim' }, e.actor ? e.actor.role : '')),
            h('td', {}, ACT[e.action] || e.action), h('td', {}, tgt(e.target)),
            h('td', { class: 'mono' }, st(e.before)), h('td', { class: 'mono' }, st(e.after)),
            h('td', {}, h('span', { class: 'badge ' + (e.result === 'ok' ? 'on' : 'unavailable') }, e.result)), h('td', {}, e.reason))))))
          : stateBox('empty', 'Nenhuma ação administrativa registrada desde que o servidor subiu.')));
    },
  };
}

// ---------------------------------------------------------------- SISTEMA
export function system(ctx) {
  const f = frame(ctx, 'Sistema', 'Estado do servidor e de onde vêm os dados.');
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/system');
      if (!ctx.alive()) return;
      const row = (k, v) => [h('span', { class: 'k' }, k), h('span', { class: 'v' }, v)];
      f.show(h('div', { class: 'cols3' },
        h('div', { class: 'panel' }, h('h2', {}, 'Servidor'), h('div', { class: 'kv' }, row('Ambiente', d.env.toUpperCase()), row('Backend de contas', d.backend_kind), row('Versão', d.server_version || '—'), row('Commit', d.commit || '—'), row('No ar há', fmtDur(d.uptime_ms)))),
        h('div', { class: 'panel' }, h('h2', {}, 'Dados do Admin'), h('div', { class: 'kv' }, row('Telemetria desde', fmtDate(d.tracking_since)), row('Admin Log persistente', d.audit_persistent ? 'sim' : 'NÃO (memória + log)'), row('Controles persistentes', d.controls_persistent ? 'sim' : 'NÃO (memória)'), row('Administradores', fmtInt(d.admins)))),
        h('div', { class: 'panel' }, h('h2', {}, 'Integrações'), h('div', { class: 'kv' }, row('Voice configurado', d.voice_configured ? 'sim' : 'não'), row('Pagamentos', 'ver a tela Vendas'))),
      ));
    },
  };
}

// ---------------------------------------------------------------- R157 · TORNEIOS DE EVENTO (XADREZ, por código)
const EV_ST = { open: ['Inscrições abertas', 'on'], closed: ['Inscrições encerradas', 'warn'], running: ['Em andamento', 'warn'], finished: ['Encerrado', 'on'], cancelled: ['Cancelado', 'off'] };
const pad2 = n => String(n).padStart(2, '0');
const localInput = iso => { if (!iso) return ''; const d = new Date(iso); return isNaN(d) ? '' : `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}T${pad2(d.getHours())}:${pad2(d.getMinutes())}`; };
function eventDialog(ev, modes, statuses) {
  return new Promise(resolve => {
    const f = (label, el) => h('label', {}, label, el);
    const name = h('input', { type: 'text', value: ev ? ev.name : '', placeholder: 'Torneio da cidade · Outubro', maxlength: 60 });
    const code = h('input', { type: 'text', value: ev ? ev.code : '', placeholder: 'MARINGA2026', maxlength: 20, style: 'text-transform:uppercase' });
    const mode = h('select', {}, modes.map(m => h('option', { value: m.id, selected: ev ? ev.mode === m.id : m.id === 'casual_10min' }, m.name)));
    const when = h('input', { type: 'datetime-local', value: ev ? localInput(ev.starts_at) : '' });
    const max = h('input', { type: 'number', min: 2, max: 256, value: ev ? ev.max_players : 16 });
    const status = h('select', {}, statuses.map(s => h('option', { value: s, selected: ev ? ev.status === s : s === 'open' }, (EV_ST[s] || [s])[0])));
    const notes = h('textarea', { rows: 3, maxlength: 500, placeholder: 'Regras, local, premiação… (os inscritos veem)' }, ev ? ev.notes : '');
    const reason = h('textarea', { rows: 2, placeholder: 'Motivo (vai para o Admin Log)', maxlength: 300 });
    const close = v => { bg.remove(); resolve(v); };
    const bg = h('div', { class: 'modal-bg', onclick: e => { if (e.target === bg) close(null); } },
      h('div', { class: 'modal', role: 'dialog', 'aria-modal': 'true' },
        h('h3', {}, ev ? 'Editar torneio' : 'Novo torneio de xadrez'),
        h('div', { class: 'fields' }, f('Nome', name), f('Código de inscrição (4 a 20 letras/números)', code), f('Ritmo das partidas', mode),
          f('Data e hora (opcional)', when), f('Vagas', max), ev ? f('Situação', status) : '', f('Observações para os jogadores', notes), f('Motivo', reason)),
        h('div', { class: 'actions' }, h('button', { class: 'btn ghost', onclick: () => close(null) }, 'Cancelar'),
          h('button', { class: 'btn ok', onclick: () => close({ name: name.value.trim(), code: code.value.trim().toUpperCase(), mode: mode.value,
            starts_at: when.value ? new Date(when.value).toISOString() : null, max_players: Number(max.value), status: ev ? status.value : 'open',
            notes: notes.value.trim(), reason: reason.value.trim() }) }, 'Salvar'))));
    document.body.append(bg); name.focus();
  });
}
const EV_ERR = { invalid_code: 'Código inválido (4 a 20 letras/números, sem espaço).', invalid_name: 'Informe o nome (3 a 60 letras).', invalid_max: 'Vagas de 2 a 256.',
  invalid_date: 'Data inválida.', code_taken: 'Esse código já é de outro torneio.', not_enough_players: 'Precisa de pelo menos 2 inscritos.',
  match_not_ready: 'Essa partida ainda não tem os dois jogadores.', migration_0021_missing: 'Banco sem a migração 0021 (torneios de evento).' };
export function events(ctx) {
  const f = frame(ctx, 'Torneios', 'Torneios de XADREZ com código: crie o torneio, passe o código para as pessoas (só quem digita o código entra pela aba TORNEIO → XADREZ do jogo), feche as inscrições, monte as chaves e marque o vencedor de cada partida. As partidas são combinadas entre os jogadores (convite de amigo no ritmo do torneio).');
  const can = () => ctx.session && ctx.session.admin && (ctx.session.admin.perms || []).includes('events.write');
  let meta = { modes: [], statuses: [] };
  const err = e => toast(EV_ERR[e && e.code] || 'Não foi possível concluir.');
  const save = async ev => {
    const v = await eventDialog(ev, meta.modes, meta.statuses);
    if (!v) return;
    try { await ctx.api.post('/admin/api/events' + (ev ? '/' + ev.id : ''), v); toast('Torneio salvo.'); } catch (e) { err(e); }
    ctx.refresh();
  };
  const quick = async (ev, status, label) => {
    try { await ctx.api.post('/admin/api/events/' + ev.id, { status }); toast(label); } catch (e) { err(e); }
    ctx.refresh();
  };
  const bracket = async ev => {
    const ok = await confirmAction({ title: 'Montar as chaves de ' + ev.name, body: `${ev.entrants.length} inscritos. As chaves são sorteadas (eliminação simples; quem sobra passa direto para a 2ª rodada). As inscrições fecham. ${ev.bracket ? 'ATENÇÃO: as chaves atuais e os resultados serão APAGADOS.' : ''}`, confirmWord: 'CHAVES', actionLabel: 'Montar chaves', danger: !!ev.bracket });
    if (!ok) return;
    try { await ctx.api.post('/admin/api/events/' + ev.id + '/bracket', { reason: ok.reason }); toast('Chaves montadas.'); } catch (e) { err(e); }
    ctx.refresh();
  };
  const result = async (ev, r, m, uid) => {
    try { await ctx.api.post('/admin/api/events/' + ev.id + '/result', { round: r, match: m, winner: uid }); toast(uid ? 'Vencedor marcado.' : 'Resultado desfeito.'); } catch (e) { err(e); }
    ctx.refresh();
  };
  const roundName = (r, n) => n - r === 1 ? 'Final' : n - r === 2 ? 'Semifinal' : n - r === 3 ? 'Quartas de final' : `Rodada ${r + 1}`;
  const bracketView = ev => {
    const nm = id => id ? (ev.names[id] || 'Jogador') : '—';
    const rounds = ev.bracket.rounds;
    return h('div', { style: 'display:flex;gap:14px;overflow-x:auto;padding:6px 0' }, rounds.map((round, r) => h('div', { style: 'min-width:220px' },
      h('div', { class: 'dim', style: 'margin-bottom:6px;font-weight:600' }, roundName(r, rounds.length)),
      round.map((x, m) => h('div', { class: 'panel', style: 'padding:8px;margin-bottom:8px' },
        [x.a, x.b].map(p => h('div', { style: 'display:flex;gap:6px;align-items:center;margin:2px 0' },
          h('span', { style: (x.winner && x.winner === p ? 'font-weight:700;color:#7be08a' : '') + ';flex:1' }, p ? nm(p) : (r === 0 ? '(passa direto)' : '—')),
          can() && p && x.a && x.b && ev.status !== 'cancelled' && x.winner !== p ? h('button', { class: 'btn', style: 'padding:2px 8px', onclick: () => result(ev, r, m, p) }, 'Venceu') : '')),
        can() && x.winner && x.a && x.b ? h('button', { class: 'btn ghost', style: 'padding:2px 8px;margin-top:4px', onclick: () => result(ev, r, m, null) }, 'Desfazer') : '')))));
  };
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/events');
      if (!ctx.alive()) return;
      if (!d.available) return f.show(stateBox('error', d.error === 'migration_0021_missing' ? 'Banco sem a migração 0021 (torneios de evento). Aplique supabase/migrations/0021_fraiha_torneios_evento.sql no SQL Editor.' : 'Torneios indisponíveis neste servidor.'));
      meta = { modes: d.modes || [], statuses: d.statuses || [] };
      const item = ev => h('div', { class: 'panel' },
        h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;align-items:center' },
          h('strong', {}, ev.name), h('span', { class: 'badge' }, 'CÓDIGO ' + ev.code),
          h('span', { class: 'badge ' + (EV_ST[ev.status] || ['', ''])[1] }, (EV_ST[ev.status] || [ev.status])[0]),
          h('span', { class: 'dim' }, `${(meta.modes.find(m => m.id === ev.mode) || { name: ev.mode }).name} · ${ev.entrants.length}/${ev.max_players} inscritos · ${ev.starts_at ? fmtDate(ev.starts_at) : 'sem data'}`),
          ev.champion ? h('span', { class: 'badge on' }, '🏆 ' + (ev.names[ev.champion] || 'Jogador')) : '',
          can() ? h('span', { style: 'margin-left:auto;display:flex;gap:8px;flex-wrap:wrap' },
            h('button', { class: 'btn', onclick: () => save(ev) }, 'Editar'),
            ev.status === 'open' ? h('button', { class: 'btn', onclick: () => quick(ev, 'closed', 'Inscrições encerradas.') }, 'Encerrar inscrições') : '',
            ev.status === 'closed' && !ev.bracket ? h('button', { class: 'btn', onclick: () => quick(ev, 'open', 'Inscrições reabertas.') }, 'Reabrir inscrições') : '',
            ev.status !== 'cancelled' && ev.status !== 'finished' ? h('button', { class: 'btn ok', onclick: () => bracket(ev) }, ev.bracket ? 'Refazer chaves' : 'Montar chaves') : '') : ''),
        ev.notes ? h('p', { class: 'dim', style: 'white-space:pre-wrap' }, ev.notes) : '',
        h('details', { style: 'margin-top:8px' }, h('summary', {}, `Inscritos (${ev.entrants.length})`),
          ev.entrants.length ? h('ol', {}, ev.entrants.map(e => h('li', {}, e.nickname, h('span', { class: 'dim' }, ' · ' + fmtDate(e.joined_at))))) : h('p', { class: 'dim' }, 'Ninguém inscrito ainda.')),
        ev.bracket ? bracketView(ev) : '');
      f.show(
        can() ? h('div', { style: 'margin:10px 0' }, h('button', { class: 'btn primary', onclick: () => save(null) }, '+ Novo torneio')) : '',
        d.items.length ? h('div', {}, d.items.map(item)) : stateBox('empty', 'Nenhum torneio criado ainda.'));
    },
  };
}

// ---------------------------------------------------------------- R161 · NOVIDADES (outdoor da Home + abas do jogo)
const NW_KIND = { banner: 'Outdoor da Home', atualizacao: 'Atualização', noticia: 'Notícia', campeonato: 'Campeonato', evento: 'Evento' };
const NW_ACT = { '': 'Sem botão', torneios: 'Abrir TORNEIOS', ranking: 'Abrir RANKING', premium: 'Abrir SEJA MEMBRO (Premium)', loja: 'Abrir LOJA (Premium)', loja_coroas: 'Abrir LOJA DE COROAS', url: 'Abrir um link (https://…)' };
const NW_ERR = { invalid_kind: 'Escolha o tipo.', invalid_title: 'Título de 2 a 90 letras.', invalid_body: 'Texto até 4000 letras.', invalid_button: 'Nome do botão até 30 letras.',
  invalid_action: 'Botão: escolha o que ele abre (ou um link começando com https://).', invalid_date: 'Data inválida.', migration_0022_missing: 'Banco sem a migração 0022 (novidades).' };
function newsDialog(it, kind0) {
  return new Promise(resolve => {
    const f = (label, el, hint) => h('label', {}, label, el, hint ? h('small', { class: 'dim', style: 'display:block' }, hint) : '');
    const kind = h('select', {}, Object.keys(NW_KIND).map(k => h('option', { value: k, selected: (it ? it.kind : kind0) === k }, NW_KIND[k])));
    const title = h('input', { type: 'text', value: it ? it.title : '', maxlength: 90, placeholder: 'Ex.: TORNEIO SÁBADO ÀS 20H · INSCREVA-SE!' });
    const body = h('textarea', { rows: 8, maxlength: 4000, placeholder: 'Texto que aparece na tela NOVIDADES (pode usar • no começo das linhas)' }, it ? it.body : '');
    const curAct = it ? it.button_action || '' : '';
    const isUrl = curAct.startsWith('https://');
    const act = h('select', {}, Object.keys(NW_ACT).map(k => h('option', { value: k, selected: isUrl ? k === 'url' : curAct === k }, NW_ACT[k])));
    const url = h('input', { type: 'text', value: isUrl ? curAct : '', placeholder: 'https://…', maxlength: 290 });
    const blabel = h('input', { type: 'text', value: it ? it.button_label : '', maxlength: 30, placeholder: 'Ex.: Ver torneios' });
    const when = h('input', { type: 'datetime-local', value: it ? localInput(it.published_at) : '' });
    const pinned = h('input', { type: 'checkbox', checked: it ? !!it.pinned : false });
    const published = h('input', { type: 'checkbox', checked: it ? it.published !== false : true });
    const reason = h('textarea', { rows: 2, placeholder: 'Motivo (vai para o Admin Log)', maxlength: 300 });
    const bodyRow = f('Texto', body), btnRow = h('div', {}, f('Botão (opcional): o que abre', act), f('Link', url), f('Nome do botão', blabel));
    const sync = () => {
      const b = kind.value === 'banner';
      bodyRow.style.display = b ? 'none' : ''; btnRow.style.display = b ? 'none' : '';
      url.parentElement.style.display = act.value === 'url' ? '' : 'none';
      title.placeholder = b ? 'Frase do outdoor (curta fica melhor; comprida corre na faixa)' : 'Título da novidade';
    };
    kind.onchange = sync; act.onchange = sync;
    const close = v => { bg.remove(); resolve(v); };
    const bg = h('div', { class: 'modal-bg', onclick: e => { if (e.target === bg) close(null); } },
      h('div', { class: 'modal', role: 'dialog', 'aria-modal': 'true', style: 'max-width:640px' },
        h('h3', {}, it ? 'Editar novidade' : 'Nova novidade'),
        h('div', { class: 'fields' }, f('Tipo', kind, 'Outdoor da Home = a frase da faixa embaixo da logo (aparece rodando se houver mais de uma).'),
          f('Título / frase', title), bodyRow, btnRow,
          f('Data de publicação (vazio = agora)', when, 'Com data no futuro, só aparece a partir dela.'),
          h('label', { style: 'display:flex;gap:8px;align-items:center' }, pinned, 'Destaque (fica no topo da aba / primeira frase do outdoor)'),
          h('label', { style: 'display:flex;gap:8px;align-items:center' }, published, 'Publicado (desmarque para esconder sem apagar)'),
          f('Motivo', reason)),
        h('div', { class: 'actions' }, h('button', { class: 'btn ghost', onclick: () => close(null) }, 'Cancelar'),
          h('button', { class: 'btn ok', onclick: () => {
            const a = act.value === 'url' ? url.value.trim() : act.value;
            close({ kind: kind.value, title: title.value.trim(), body: body.value, button_action: a, button_label: a ? blabel.value.trim() : '',
              published_at: when.value ? new Date(when.value).toISOString() : (it ? it.published_at : null), pinned: pinned.checked, published: published.checked, reason: reason.value.trim() });
          } }, 'Salvar'))));
    document.body.append(bg); sync(); title.focus();
  });
}
export function news(ctx) {
  const f = frame(ctx, 'Novidades', 'O que aparece no jogo: a frase do OUTDOOR (faixa embaixo da logo da Home) e as abas ATUALIZAÇÕES, NOTÍCIAS, CAMPEONATOS e EVENTOS (o jogador toca no outdoor e abre). Muda no jogo em até 1 minuto.');
  const can = () => ctx.session && ctx.session.admin && (ctx.session.admin.perms || []).includes('events.write');
  const err = e => toast(NW_ERR[e && e.code] || 'Não foi possível concluir.');
  const save = async (it, kind0) => {
    const v = await newsDialog(it, kind0 || 'noticia');
    if (!v) return;
    try { await ctx.api.post('/admin/api/news' + (it ? '/' + it.id : ''), v); toast('Novidade salva.'); } catch (e) { err(e); }
    ctx.refresh();
  };
  const toggle = async (it, patch, label) => {
    try { await ctx.api.post('/admin/api/news/' + it.id, patch); toast(label); } catch (e) { err(e); }
    ctx.refresh();
  };
  const del = async it => {
    const ok = await confirmAction({ title: 'Apagar "' + it.title + '"', body: 'Some do jogo na hora. Para só esconder, use "Esconder".', confirmWord: 'APAGAR', actionLabel: 'Apagar', danger: true });
    if (!ok) return;
    try { await ctx.api.post('/admin/api/news/' + it.id + '/delete', { reason: ok.reason }); toast('Apagada.'); } catch (e) { err(e); }
    ctx.refresh();
  };
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/news');
      if (!ctx.alive()) return;
      if (!d.available) return f.show(stateBox('error', d.error === 'migration_0022_missing' ? 'Banco sem a migração 0022 (novidades). Aplique supabase/migrations/0022_fraiha_novidades.sql no SQL Editor.' : 'Novidades indisponíveis neste servidor.'));
      const row = it => h('div', { class: 'panel', style: it.published ? '' : 'opacity:.6' },
        h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;align-items:center' },
          h('span', { class: 'badge' }, NW_KIND[it.kind] || it.kind), it.pinned ? h('span', { class: 'badge on' }, 'DESTAQUE') : '',
          it.published ? '' : h('span', { class: 'badge off' }, 'ESCONDIDA'),
          h('strong', {}, it.title), h('span', { class: 'dim' }, fmtDate(it.published_at)),
          can() ? h('span', { style: 'margin-left:auto;display:flex;gap:8px;flex-wrap:wrap' },
            h('button', { class: 'btn', onclick: () => save(it) }, 'Editar'),
            h('button', { class: 'btn', onclick: () => toggle(it, { published: !it.published }, it.published ? 'Escondida.' : 'Publicada.') }, it.published ? 'Esconder' : 'Publicar'),
            h('button', { class: 'btn', onclick: () => toggle(it, { pinned: !it.pinned }, it.pinned ? 'Sem destaque.' : 'Em destaque.') }, it.pinned ? 'Tirar destaque' : 'Destacar'),
            h('button', { class: 'btn danger', onclick: () => del(it) }, 'Apagar')) : ''),
        it.body ? h('p', { class: 'dim', style: 'white-space:pre-wrap;margin:6px 0 0' }, it.body.length > 400 ? it.body.slice(0, 400) + '…' : it.body) : '',
        it.button_label ? h('p', { class: 'dim', style: 'margin:4px 0 0' }, 'Botão: ' + it.button_label + ' → ' + (NW_ACT[it.button_action] || it.button_action)) : '');
      const banners = d.items.filter(x => x.kind === 'banner'), others = d.items.filter(x => x.kind !== 'banner');
      f.show(
        h('div', { class: 'panel' }, h('h2', {}, 'Outdoor da Home'),
          h('p', { class: 'dim' }, banners.some(b => b.published) ? 'Frases publicadas aparecem rodando na faixa (a de destaque primeiro).' : 'Nenhuma frase publicada: a faixa mostra "ESTRATÉGIA PARA IR MAIS LONGE".'),
          can() ? h('button', { class: 'btn primary', style: 'margin:6px 0', onclick: () => save(null, 'banner') }, '+ Nova frase do outdoor') : '',
          banners.length ? h('div', {}, banners.map(row)) : ''),
        h('div', { class: 'panel' }, h('h2', {}, 'Abas do jogo (Atualizações, Notícias, Campeonatos, Eventos)'),
          can() ? h('button', { class: 'btn primary', style: 'margin:6px 0', onclick: () => save(null, 'atualizacao') }, '+ Nova novidade') : '',
          others.length ? h('div', {}, others.map(row)) : stateBox('empty', 'Nenhuma novidade ainda.')));
    },
  };
}
