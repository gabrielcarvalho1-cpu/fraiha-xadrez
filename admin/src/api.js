// FRAIHA Admin · cliente da API administrativa. O token fica SÓ na memória da aba (recarregar = entrar de novo).
// Quem decide permissões é o servidor; aqui só exibimos o erro que ele devolve.
import { ENVIRONMENTS, SUPABASE, REQUEST_TIMEOUT_MS } from './config.js';

export class ApiError extends Error {
  constructor(kind, status = 0, code = '', detail = '') { super(code || kind); this.kind = kind; this.status = status; this.code = code; this.detail = detail; }
  get text() {
    if (this.kind === 'timeout') return 'O servidor não respondeu a tempo.';
    if (this.kind === 'network') return 'Sem conexão com o servidor.';
    return ({
      auth_required: 'Sessão ausente. Entre novamente.', invalid_session: 'Sessão inválida ou expirada. Entre novamente.',
      not_admin: 'Esta conta NÃO é administradora (verificado pelo servidor).', forbidden: 'Seu papel não tem permissão para esta ação.',
      admin_disabled: 'Admin desligado neste servidor (FRAIHA_ADMIN_USERS não configurado).', origin_not_allowed: 'Origem do Admin não autorizada pelo servidor.',
      rate_limited: 'Muitas requisições. Aguarde um pouco.', reason_required: 'Informe o motivo.', confirmation_required: 'Confirmação incorreta.',
      body_too_large: 'Requisição grande demais.', not_found: 'Não encontrado.', server_error: 'Erro interno do servidor.',
    })[this.code] || `Erro ${this.status || ''} ${this.code || ''}`.trim();
  }
}

export class Api {
  constructor(envKey, token) { this.envKey = envKey; this.env = ENVIRONMENTS[envKey]; this.token = token; }
  async request(path, { method = 'GET', body, timeout = REQUEST_TIMEOUT_MS } = {}) {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), timeout);
    let res;
    try {
      res = await fetch(this.env.api + path, { method, signal: ctl.signal, credentials: 'omit', cache: 'no-store',
        headers: { Authorization: 'Bearer ' + this.token, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
        body: body !== undefined ? JSON.stringify(body) : undefined });
    } catch (e) { throw new ApiError(e.name === 'AbortError' ? 'timeout' : 'network'); }
    finally { clearTimeout(t); }
    let data = null; try { data = await res.json(); } catch { /* corpo vazio */ }
    if (!res.ok) throw new ApiError(res.status === 401 ? 'auth' : res.status === 403 ? 'forbidden' : res.status >= 500 ? 'server' : 'http', res.status, data && data.error, data && data.detail);
    return data;
  }
  get(path) { return this.request(path); }
  post(path, body) { return this.request(path, { method: 'POST', body }); }
}

// Login: STAGING/PRODUCTION usam a conta FRAIHA (Supabase Auth, chave PUBLICÁVEL). LOCAL usa token DEV.
export async function login(envKey, { email, password, devName }) {
  const env = ENVIRONMENTS[envKey];
  if (!env) throw new ApiError('http', 0, 'bad_env');
  if (env.auth === 'dev') {
    if (!/^[A-Za-z0-9_.-]{1,32}$/.test(devName || '')) throw new ApiError('http', 0, 'bad_dev_name');
    return 'dev:' + devName;
  }
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), REQUEST_TIMEOUT_MS);
  try {
    const res = await fetch(SUPABASE.url + '/auth/v1/token?grant_type=password', { method: 'POST', signal: ctl.signal, credentials: 'omit',
      headers: { apikey: SUPABASE.publishableKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
    const d = await res.json().catch(() => ({}));
    if (!res.ok || !d.access_token) throw new ApiError('auth', res.status, 'login_failed');
    return d.access_token;
  } catch (e) { if (e instanceof ApiError) throw e; throw new ApiError(e.name === 'AbortError' ? 'timeout' : 'network'); }
  finally { clearTimeout(t); }
}
