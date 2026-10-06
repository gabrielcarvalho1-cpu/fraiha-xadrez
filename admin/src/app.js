// FRAIHA Admin · casca da aplicação: login, ambiente, navegação, atualização automática e reconexão.
import { ENVIRONMENTS } from './config.js';
import { Api, ApiError, login, remoteLogout } from './api.js';
import { h, toast, closeAllModals } from './ui.js';
import * as V from './views/index.js';

const ROUTES = [
  { id: 'dashboard', label: 'Dashboard', ico: '◧', view: V.dashboard, every: 5000 },
  { id: 'live', label: 'Ao Vivo', ico: '◉', view: V.live, every: 5000 },
  { id: 'queues', label: 'Filas', ico: '☰', view: V.queues, every: 3000 },
  { id: 'matches', label: 'Partidas', ico: '♞', view: V.matches, every: 5000 },
  { id: 'players', label: 'Jogadores', ico: '☺', view: V.players, every: 0 },
  { id: 'club', label: 'Clube', ico: '◆', view: V.club, every: 0 },
  { id: 'founder', label: 'Founder', ico: '♛', view: V.founder, every: 0 },
  { sep: true },
  { id: 'audit', label: 'Admin Log', ico: '≡', view: V.audit, every: 10000 },
  { id: 'system', label: 'Sistema', ico: '⚙', view: V.system, every: 15000 },
];

// epoch muda a cada login/logout: qualquer callback/promise de uma sessão anterior vira no-op.
const S = { api: null, session: null, envKey: '', timer: null, fails: 0, lastOk: 0, viewToken: 0, epoch: 0 };
const root = document.getElementById('app');

function route() {
  const [id, ...rest] = location.hash.replace(/^#\/?/, '').split('/');
  return { r: ROUTES.find(x => x.id === id) || ROUTES[0], arg: rest.join('/') };
}

// Encerra a sessão administrativa no CLIENTE de forma fail-closed (o servidor continua sendo a autoridade):
// para timers, revoga o cliente da API (aborta requisições em voo e recusa novas), fecha confirmações
// pendentes, apaga identidade/dados da tela e invalida views antigas.
function endSession({ remote = false } = {}) {
  S.epoch++; S.viewToken++;
  clearTimeout(S.timer); S.timer = null;
  const api = S.api;
  if (api) { const tok = api.token; api.revoke(); if (remote) remoteLogout(api.envKey, tok); }
  closeAllModals();
  window.onhashchange = null;
  Object.assign(S, { api: null, session: null, envKey: '', fails: 0, lastOk: 0 });
}

function renderLogin(error = '') {
  if (S.api || S.session) endSession();
  const envSel = h('select', { name: 'env' }, Object.entries(ENVIRONMENTS).map(([k, e]) => h('option', { value: k }, e.label)));
  const email = h('input', { type: 'text', name: 'email', autocomplete: 'username', placeholder: 'email da sua conta FRAIHA' });
  const pass = h('input', { type: 'password', name: 'password', autocomplete: 'current-password' });
  const dev = h('input', { type: 'text', name: 'dev', placeholder: 'nome dev (ex.: boss)', autocomplete: 'off' });
  const supaRows = [h('label', {}, 'E-mail', email), h('label', {}, 'Senha', pass)];
  const devRows = [h('label', {}, 'Conta DEV (servidor local com FRAIHA_DEV_AUTH=1)', dev)];
  const msg = h('div', { class: error ? 'banner err' : 'hidden' }, error);
  const btn = h('button', { class: 'btn primary', type: 'submit' }, 'Entrar');
  const sync = () => { const dv = ENVIRONMENTS[envSel.value].auth === 'dev'; supaRows.forEach(r => r.classList.toggle('hidden', dv)); devRows.forEach(r => r.classList.toggle('hidden', !dv)); };
  envSel.addEventListener('change', sync);
  const form = h('form', { onsubmit: async e => {
    e.preventDefault(); btn.disabled = true; btn.textContent = 'Entrando…'; msg.className = 'hidden';
    const epoch = S.epoch;
    let api = null;
    try {
      const token = await login(envSel.value, { email: email.value.trim(), password: pass.value, devName: dev.value.trim() });
      pass.value = '';
      api = new Api(envSel.value, token);
      const session = await api.get('/admin/api/session');   // o SERVIDOR decide se é admin
      if (epoch !== S.epoch || !document.body.contains(form)) { api.revoke(); return; }   // login antigo chegando tarde
      S.epoch++;
      Object.assign(S, { api, session, envKey: envSel.value, fails: 0 });
      if (!location.hash) location.hash = '#/dashboard';
      renderShell();
    } catch (err) {
      if (api) api.revoke();
      if (epoch !== S.epoch) return;
      msg.textContent = err instanceof ApiError ? (err.code === 'login_failed' ? 'E-mail ou senha incorretos.' : err.text) : 'Falha inesperada.';
      msg.className = 'banner err'; btn.disabled = false; btn.textContent = 'Entrar';
    }
  } }, h('label', {}, 'Ambiente', envSel), supaRows, devRows, msg, btn);
  root.replaceChildren(h('div', { class: 'login' }, h('div', { class: 'box' },
    h('h1', {}, h('span', { class: 'crest brand' }, h('span', { class: 'crest' }, '♜')), 'FRAIHA ADMIN'),
    h('p', { class: 'muted' }, 'Acesso restrito. A permissão é verificada pelo servidor a cada requisição.'), form)));
  sync();
}

function renderShell() {
  const envName = (S.session && S.session.env) || 'unknown';
  const expected = S.envKey === 'local' ? ['local', 'dev'] : [S.envKey];
  const mismatch = !expected.includes(envName);
  const envText = { local: 'LOCAL', dev: 'DEV', staging: 'STAGING', production: 'PRODUCTION — DADOS REAIS' }[envName] || 'AMBIENTE DESCONHECIDO';
  const side = h('nav', { class: 'side', 'aria-label': 'Seções' }, ROUTES.map(r => r.sep ? h('div', { class: 'sep' }) : h('a', { href: '#/' + r.id, dataset: { route: r.id } }, h('span', { class: 'ico' }, r.ico), r.label)));
  const conn = h('span', { class: 'conn' }, h('span', { class: 'dot', id: 'conn-dot' }), h('span', { id: 'conn-text' }, 'conectando…'));
  const top = h('header', { class: 'top' },
    h('div', { class: 'brand' }, h('span', { class: 'crest' }, '♜'), 'FRAIHA ', h('small', {}, 'ADMIN')),
    h('span', { class: 'badge ' + (envName === 'production' ? 'off' : 'gold') }, envText),
    h('div', { class: 'spacer' }), conn,
    h('span', { class: 'who' }, h('b', {}, S.session.admin.name), ' · ', S.session.admin.role),
    h('button', { class: 'btn ghost', onclick: logout }, 'Sair'));
  const main = h('main', { id: 'view' });
  root.replaceChildren(h('div', { class: 'shell' },
    h('div', { class: 'envbar ' + envName }, envName === 'production' ? '⚠ PRODUCTION — AÇÕES AFETAM JOGADORES REAIS' : `AMBIENTE ${envText}` + (mismatch ? ` · ATENÇÃO: o servidor diz "${envName}"` : '')),
    top, side, main));
  window.onhashchange = () => mount();
  mount();
}

function logout() { endSession({ remote: true }); history.replaceState(null, '', location.pathname); renderLogin(); }

function setConn(kind, text) {
  const d = document.getElementById('conn-dot'), t = document.getElementById('conn-text');
  if (d) d.className = 'dot ' + kind; if (t) t.textContent = text;
}

// Monta a view e controla a atualização: intervalo da rota, pausa com aba oculta, backoff em falha.
async function mount() {
  clearTimeout(S.timer);
  const { r, arg } = route();
  document.querySelectorAll('.side a').forEach(a => a.classList.toggle('on', a.dataset.route === r.id));
  const main = document.getElementById('view'); if (!main) return;
  const token = ++S.viewToken, epoch = S.epoch;
  const alive = () => token === S.viewToken && epoch === S.epoch && !!S.api;
  const ctx = { api: S.api, session: S.session, arg, el: main, refresh: () => tick(true), alive };
  const view = r.view(ctx);
  const tick = async (manual = false) => {
    if (!alive()) return;
    try {
      await view.load();
      if (!alive()) return;   // resposta tardia de sessão/tela antiga: não mexe em nada
      S.fails = 0; S.lastOk = Date.now(); setConn('ok', r.every ? `ao vivo · ${new Date().toLocaleTimeString('pt-BR')}` : `atualizado ${new Date().toLocaleTimeString('pt-BR')}`);
    } catch (err) {
      if (!alive() || (err instanceof ApiError && err.kind === 'revoked')) return;   // sessão encerrada: silêncio
      if (!(err instanceof ApiError)) { console.error(err); err = new ApiError('server', 0, 'client_error'); }
      if (err.kind === 'auth') { endSession(); toast(err.text, 'err'); return renderLogin(err.text); }
      S.fails++;
      view.error && view.error(err, S.lastOk);
      setConn(err.kind === 'network' || err.kind === 'timeout' ? 'bad' : 'warn', `${err.text} · nova tentativa em ${Math.round(backoff() / 1000)} s`);
    }
    if (!alive()) return;
    const wait = S.fails ? backoff() : r.every;
    if (wait && !manual) S.timer = setTimeout(() => (document.hidden ? waitVisible().then(() => alive() && tick()) : tick()), wait);
  };
  await tick();
}
const backoff = () => Math.min(30000, 2000 * 2 ** Math.min(4, S.fails - 1));
const waitVisible = () => new Promise(res => { const f = () => { if (!document.hidden) { document.removeEventListener('visibilitychange', f); res(); } }; document.addEventListener('visibilitychange', f); });

renderLogin();
