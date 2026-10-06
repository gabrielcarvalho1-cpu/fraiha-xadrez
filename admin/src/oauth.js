// FRAIHA Admin · ENTRAR COM GOOGLE pelo Supabase Auth — o MESMO fluxo do jogo Web
// (account/account_service.gd: /auth/v1/authorize?provider=google&redirect_to=… → volta com
// #access_token=… no endereço). Sem SDK, sem segredo: só a URL do projeto (pública).
//
// Login com Google NÃO é autorização administrativa: o token obtido aqui só vira sessão do Admin se o
// SERVIDOR aceitar em /admin/api/session (token verificado no Supabase + UUID na FRAIHA_ADMIN_USERS).
//
// Segurança do retorno:
// - redirect_to = endereço CANÔNICO desta página (origem + caminho, sem query/hash); nunca vem da URL
//   ou de parâmetro → sem open redirect. O Supabase ainda confere contra a lista de Redirect URLs.
// - o retorno só é aceito se ESTA aba iniciou o login há pouco (marcador de uso único em sessionStorage,
//   sem credencial nenhuma): um link pronto com #access_token=<conta de outra pessoa> é ignorado.
// - tokens saem da barra de endereço imediatamente; o refresh token e o token do Google são descartados;
//   o access token fica só na memória (como no login por senha).
import { ENVIRONMENTS, SUPABASE } from './config.js';

const KEY = 'fraiha_admin_oauth';
const MAX_AGE_MS = 10 * 60 * 1000;

export function adminReturnUrl(loc = window.location) {
  const path = loc.pathname.replace(/\/index\.html$/, '/');
  return loc.origin + path;
}

export function googleAuthorizeUrl(redirectTo) {
  return SUPABASE.url + '/auth/v1/authorize?provider=google&redirect_to=' + encodeURIComponent(redirectTo);
}

function store() { try { return window.sessionStorage; } catch { return null; } }

// Inicia o login: grava o marcador (ambiente + horário; nada secreto) e sai para o Supabase/Google.
export function startGoogle(envKey, { loc = window.location, storage = store(), now = Date.now(), go = u => loc.assign(u) } = {}) {
  const env = ENVIRONMENTS[envKey];
  if (!env || env.auth !== 'supabase') throw new Error('google_not_available');
  if (!storage) throw new Error('storage_unavailable');
  storage.setItem(KEY, JSON.stringify({ env: envKey, at: now }));
  go(googleAuthorizeUrl(adminReturnUrl(loc)));
}

// Lê (e LIMPA) o retorno do Google no carregamento da página.
// → null (nada a fazer) | { error } | { envKey, token }
export function consumeGoogleReturn({ loc = window.location, history = window.history, storage = store(), now = Date.now() } = {}) {
  const hash = new URLSearchParams(String(loc.hash || '').replace(/^#/, ''));
  const query = new URLSearchParams(String(loc.search || '').replace(/^\?/, ''));
  const token = hash.get('access_token');
  const err = hash.get('error') || query.get('error');
  const errText = hash.get('error_description') || query.get('error_description') || err;
  if (!token && !err) return null;
  try { history.replaceState(null, '', loc.pathname); } catch { /* ignore */ }   // tokens fora da barra JÁ
  let pending = null;
  try { pending = JSON.parse(storage && storage.getItem(KEY) || 'null'); } catch { pending = null; }
  try { storage && storage.removeItem(KEY); } catch { /* ignore */ }               // uso único
  const valid = pending && typeof pending.at === 'number' && now - pending.at >= 0 && now - pending.at <= MAX_AGE_MS
    && ENVIRONMENTS[pending.env] && ENVIRONMENTS[pending.env].auth === 'supabase';
  if (!valid) return { error: 'Retorno de login ignorado: este navegador não iniciou um login com Google agora. Tente de novo.' };
  if (err) return { error: 'Login com Google não concluído: ' + String(errText).slice(0, 200) };
  // mesmo formato de token aceito pelo servidor (Bearer); quem decide se vale é o servidor
  if (!/^[A-Za-z0-9._:\-]{8,4096}$/.test(token)) return { error: 'Login com Google não concluído: resposta inválida.' };
  return { envKey: pending.env, token };
}
