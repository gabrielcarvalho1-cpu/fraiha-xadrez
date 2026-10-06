// FRAIHA Admin · telas. Regra: número só aparece quando o servidor o entrega; o que não existe aparece
// como INDISPONÍVEL com o motivo. Ação sem backend aparece desabilitada com "BACKEND NECESSÁRIO".
import { h, metricCard, statusBadge, stateBox, loadingCards, lineChart, confirmAction, toast, unavailable,
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
          q.by_mode.length ? h('p', { class: 'dim', style: 'margin:10px 0 0;font-size:12px' }, q.by_mode.map(m => `${m.mode}: ${m.waiting}`).join(' · ')) : '',
          h('div', { class: 'qfoot' },
            h('span', { class: 'dim', style: 'font-size:12px' }, q.changed_at ? `${q.enabled ? 'ativado' : 'desativado'} por ${q.changed_by ? q.changed_by.name : '?'} · ${fmtAgo(q.changed_at)}` : 'sem alterações desde o início do servidor'),
            canWrite ? h('button', { class: 'btn ' + (q.enabled ? 'danger' : 'ok'), onclick: () => toggle(q), dataset: { action: 'toggle' } }, q.enabled ? 'Desativar fila' : 'Ativar fila')
              : h('button', { class: 'btn', disabled: true, title: 'Seu papel é só leitura' }, 'Somente leitura'))))),
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
  const f = frame(ctx, 'Perfil do jogador', 'Visão administrativa (somente leitura nesta versão).');
  const disabledAction = label => h('button', { class: 'btn', disabled: true, title: 'INDISPONÍVEL — BACKEND NECESSÁRIO' }, label);
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
            h('span', { class: 'k' }, 'Fila atual'), h('span', { class: 'v' }, w.place === 'queue' ? `${w.mode} · ${fmtDur(w.wait_ms)}` : '—'))),
          h('div', { class: 'panel' }, h('h2', {}, 'Clube FRAIHA'), h('div', { class: 'kv' },
            h('span', { class: 'k' }, 'Status'), h('span', { class: 'v' }, h('span', { class: 'badge ' + (d.club.status === 'ATIVO' ? 'gold' : entErr ? 'off' : 'unavailable'), id: 'club-status' }, d.club.status)),
            h('span', { class: 'k' }, 'Plano'), h('span', { class: 'v dim' }, d.club.plan.note),
            h('span', { class: 'k' }, 'Origem'), h('span', { class: 'v' }, entErr ? h('span', { class: 'unav' }, 'INDISPONÍVEL') : d.club.source.value || h('span', { class: 'dim' }, '—')),
            h('span', { class: 'k' }, 'Início'), h('span', { class: 'v dim' }, 'migration necessária'),
            h('span', { class: 'k' }, 'Expiração'), h('span', { class: 'v' }, entErr ? h('span', { class: 'unav' }, 'INDISPONÍVEL') : d.club.expires_at.value ? fmtDate(d.club.expires_at.value) : '—'),
            h('span', { class: 'k' }, 'Renovação'), h('span', { class: 'v dim' }, 'backend necessário'),
            h('span', { class: 'k' }, 'Observação admin'), h('span', { class: 'v dim' }, 'migration necessária')),
            h('div', { class: 'row', style: 'margin-top:12px' }, disabledAction('Conceder Clube'), disabledAction('Alterar'), disabledAction('Revogar')),
            h('p', { class: 'dim', style: 'font-size:12px' }, 'INDISPONÍVEL — BACKEND NECESSÁRIO: concessão manual exige endpoint de entitlement + audit persistente (área protegida de pagamentos).')),
          h('div', { class: 'panel' }, h('h2', {}, 'Pacote Fundador'), h('div', { class: 'kv' },
            h('span', { class: 'k' }, 'Founder'), h('span', { class: 'v', id: 'founder-value' }, d.founder.status === 'unavailable' ? h('span', { class: 'badge off' }, 'INDISPONÍVEL') : d.founder.value ? h('span', { class: 'badge gold' }, 'SIM') : 'NÃO'),
            h('span', { class: 'k' }, 'Desde'), h('span', { class: 'v' }, fmtDate(d.founder.since)),
            h('span', { class: 'k' }, 'Edição/nível'), h('span', { class: 'v dim' }, 'ainda não definido'),
            h('span', { class: 'k' }, 'Badge / moldura'), h('span', { class: 'v dim' }, 'futuro')),
            h('div', { class: 'row', style: 'margin-top:12px' }, disabledAction('Conceder Founder'), disabledAction('Revogar')),
            h('p', { class: 'dim', style: 'font-size:12px' }, 'INDISPONÍVEL — BACKEND NECESSÁRIO.'))),
        h('div', { class: 'panel' }, h('h2', {}, 'Ranked (por modo)'), ranked.length ? h('div', { class: 'tablewrap' }, h('table', {},
          h('thead', {}, h('tr', {}, ['Modo', 'Liga', 'PL', 'Partidas', 'Vitórias', 'Derrotas', 'Empates', 'Maior liga'].map(t => h('th', {}, t)))),
          h('tbody', {}, ranked.map(([k, s]) => h('tr', {}, h('td', {}, MODE_NAME[k]), h('td', {}, LEAGUES[s.league] || s.league), h('td', {}, fmtInt(s.pl)), h('td', {}, fmtInt(s.matches)), h('td', {}, fmtInt(s.wins)), h('td', {}, fmtInt(s.losses)), h('td', {}, fmtInt(s.draws)), h('td', {}, LEAGUES[s.highest_league] || '—'))))))
          : d.ranked && !d.ranked.ok ? readErr(d.ranked) : stateBox('empty', 'Sem estatísticas de Ranked.'),
          h('p', { class: 'dim', style: 'font-size:12px' }, 'O FRAIHA usa liga + PL por modo (não Elo numérico).')),
        h('div', { class: 'panel' }, h('h2', {}, 'Outros modos'), modes.length ? h('div', { class: 'mini' }, modes.map(([k, s]) => h('div', {}, h('span', { class: 'dim' }, (FAMILY_LABEL[k] || k)), h('b', {}, `${fmtInt(s.wins)} V · ${fmtInt(s.losses)} D`)))) : d.modes && !d.modes.ok ? readErr(d.modes) : stateBox('empty', 'Sem registros.')));
    },
  };
}

// ---------------------------------------------------------------- CLUBE / FOUNDER
function entitlementView(ctx, kind) {
  const isClub = kind === 'club';
  const f = frame(ctx, isClub ? 'Clube FRAIHA' : 'Pacote Fundador', isClub ? 'Estrutura preparada; planos comerciais ainda não definidos (nada fixo no código).' : 'Estrutura preparada; preço e benefícios ainda não definidos.');
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/players?q=');
      if (!ctx.alive()) return;
      const list = d.items.filter(p => isClub ? (p.club === 'ATIVO' || p.club === 'EXPIRADO') : p.founder === true);
      f.show(
        d.entitlements_read && d.entitlements_read !== 'ok' ? h('div', { class: 'banner err' }, 'ERRO DE CONSULTA dos benefícios: a lista abaixo pode estar incompleta (não significa que ninguém possui).') : '',
        h('div', { class: 'banner warn' }, 'Conceder / alterar / revogar: INDISPONÍVEL — BACKEND NECESSÁRIO. Precisa de endpoint server-side de entitlement + Admin Log persistente (migration proposta). Área protegida (pagamentos): só com sua autorização.'),
        h('div', { class: 'panel' }, h('h2', {}, isClub ? 'Assinantes encontrados' : 'Founders encontrados', ' ', statusBadge('partial')),
          h('p', { class: 'dim', style: 'font-size:12px;margin-top:-6px' }, 'Amostra: entre os jogadores com login mais recente (até 50). Lista completa precisa de consulta dedicada no backend.'),
          list.length ? h('table', {}, h('thead', {}, h('tr', {}, ['Jogador', isClub ? 'Status' : 'Founder', 'Último login'].map(t => h('th', {}, t)))),
            h('tbody', {}, list.map(p => h('tr', { class: 'click', onclick: () => { location.hash = '#/players/' + p.user_id; } }, h('td', {}, p.nickname), h('td', {}, h('span', { class: 'badge gold' }, isClub ? p.club : 'SIM')), h('td', {}, fmtAgo(p.last_login_at))))))
            : stateBox('empty', 'Nenhum encontrado na amostra.')),
        h('div', { class: 'panel' }, h('h2', {}, 'Campos preparados'), h('div', { class: 'kv' },
          ...(isClub ? ['Plano', 'Origem', 'Início', 'Expiração', 'Renovação', 'Observação administrativa'] : ['Founder SIM/NÃO', 'Badge', 'Moldura', 'Cosméticos', 'Benefícios', 'Edição/nível'])
            .flatMap(k => [h('span', { class: 'k' }, k), h('span', { class: 'v dim' }, ['Origem', 'Expiração', 'Founder SIM/NÃO'].includes(k) ? 'existe no banco (leitura)' : 'a definir / migration')]))));
    },
  };
}
export const club = ctx => entitlementView(ctx, 'club');
export const founder = ctx => entitlementView(ctx, 'founder');

// ---------------------------------------------------------------- ADMIN LOG
export function audit(ctx) {
  const f = frame(ctx, 'Admin Log', 'Toda ação administrativa real é registrada pelo SERVIDOR antes de responder.');
  const ACT = { 'queue.disable': 'desativou', 'queue.enable': 'ativou' };
  return {
    error: f.error,
    async load() {
      const d = await ctx.api.get('/admin/api/audit?limit=200');
      if (!ctx.alive()) return;
      f.show(
        d.persistent ? '' : h('div', { class: 'banner warn' }, 'Persistência: memória do servidor + linha "[admin-audit]" no log do Render. Tabela durável = migration proposta (não aplicada).'),
        h('div', { class: 'panel' }, d.items.length ? h('div', { class: 'tablewrap' }, h('table', {}, h('thead', {}, h('tr', {}, ['Quando', 'Administrador', 'Ação', 'Alvo', 'Antes', 'Depois', 'Resultado', 'Motivo'].map(t => h('th', {}, t)))),
          h('tbody', {}, d.items.map(e => h('tr', {}, h('td', {}, fmtDate(e.at)), h('td', {}, e.actor ? e.actor.name : '—', h('div', { class: 'dim' }, e.actor ? e.actor.role : '')),
            h('td', {}, ACT[e.action] || e.action), h('td', {}, e.target && e.target.family ? FAMILY_LABEL[e.target.family] : JSON.stringify(e.target)),
            h('td', { class: 'mono' }, e.before ? (e.before.enabled ? 'ativo' : 'desativado') : '—'), h('td', { class: 'mono' }, e.after ? (e.after.enabled ? 'ativo' : 'desativado') : '—'),
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
        h('div', { class: 'panel' }, h('h2', {}, 'Integrações'), h('div', { class: 'kv' }, row('Voice configurado', d.voice_configured ? 'sim' : 'não'), row('Pagamentos', 'fora do Admin V1'))),
      ));
    },
  };
}
