// FRAIHA Admin · cliente da API administrativa. O token fica SÓ na memória da aba (recarregar = entrar de novo).
// Quem decide permissões é o servidor; aqui só exibimos o erro que ele devolve.
import { ENVIRONMENTS, SUPABASE, REQUEST_TIMEOUT_MS } from './config.js';

export class ApiError extends Error {
  constructor(kind, status = 0, code = '', detail = '') { super(code || kind); this.kind = kind; this.status = status; this.code = code; this.detail = detail; }
  get text() {
    if (this.kind === 'timeout') return 'O servidor não respondeu a tempo.';
    if (this.kind === 'revoked') return 'Sessão encerrada.';
    if (this.kind === 'network') return 'Sem conexão com o servidor.';
    return ({
      auth_required: 'Sessão ausente. Entre novamente.', invalid_session: 'Sessão inválida ou expirada. Entre novamente.',
      not_admin: 'Esta conta NÃO é administradora (verificado pelo servidor).', forbidden: 'Seu papel não tem permissão para esta ação.',
      admin_disabled: 'Admin desligado neste servidor (FRAIHA_ADMIN_USERS não configurado).', origin_not_allowed: 'Origem do Admin não autorizada pelo servidor.',
      rate_limited: 'Muitas requisições. Aguarde um pouco.', reason_required: 'Informe o motivo.', confirmation_required: 'Confirmação incorreta.',
      body_too_large: 'Requisição grande demais.', not_found: 'Não encontrado.', server_error: 'Erro interno do servidor.', bad_response: 'Resposta inválida do servidor.',
    })[this.code] || `Erro ${this.status || ''} ${this.code || ''}`.trim();
  }
}

export class Api {
  constructor(envKey, token) { this.envKey = envKey; this.env = ENVIRONMENTS[envKey]; this.token = token; this.revoked = false; this.inflight = new Set(); this.onUnauthorized = null; }
  // Ponto ÚNICO de tratamento de 401: qualquer resposta 401 da API (polling, ação, leitura) revoga este
  // cliente (aborta o que estiver em voo, recusa novas, apaga o token) e avisa a sessão uma única vez.
  // Só vale para um cliente já instalado como sessão (onUnauthorized definido); no login o erro é só exibido.
  // 400/403/5xx/timeout/rede NÃO passam por aqui e não encerram a sessão.
  unauthorized(err) {
    const cb = this.onUnauthorized;
    if (!cb || this.revoked) return;
    this.onUnauthorized = null;
    this.revoke();
    try { cb(err); } catch (e) { console.error(e); }
  }
  // Logout / troca de identidade: nenhuma requisição desta sessão sai ou termina depois disso.
  revoke() { this.revoked = true; this.token = ''; for (const c of this.inflight) { try { c.abort(); } catch { /* já abortada */ } } this.inflight.clear(); }
  // O prazo cobre a operação INTEIRA: conexão, cabeçalhos E leitura/parse do corpo (auditoria: corpo travado).
  async request(path, { method = 'GET', body, timeout = REQUEST_TIMEOUT_MS } = {}) {
    if (this.revoked) throw new ApiError('revoked', 0, 'session_ended');
    const ctl = new AbortController(); this.inflight.add(ctl);
    let timedOut = false, timer;
    const deadline = new Promise((_, rej) => { timer = setTimeout(() => { timedOut = true; ctl.abort(); rej(new ApiError('timeout')); }, timeout); });
    deadline.catch(() => {});   // evita rejeição solta; quem decide é o race abaixo
    const abortRace = p => Promise.race([p, deadline]);
    try {
      const res = await abortRace(fetch(this.env.api + path, { method, signal: ctl.signal, credentials: 'omit', cache: 'no-store',
        headers: { Authorization: 'Bearer ' + this.token, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
        body: body !== undefined ? JSON.stringify(body) : undefined }));
      const text = await abortRace(res.text());
      if (this.revoked) throw new ApiError('revoked', 0, 'session_ended');
      if (res.status === 401) {   // antes do parse: 401 com corpo vazio/inválido também encerra a sessão
        let d = null; try { d = text ? JSON.parse(text) : null; } catch { /* corpo irrelevante */ }
        const err = new ApiError('auth', 401, (d && d.error) || 'invalid_session', d && d.detail);
        this.unauthorized(err);
        throw err;
      }
      let data = null;
      if (text) { try { data = JSON.parse(text); } catch { throw new ApiError('server', res.status, 'bad_response'); } }
      if (!res.ok) throw new ApiError(res.status === 401 ? 'auth' : res.status === 403 ? 'forbidden' : res.status >= 500 ? 'server' : 'http', res.status, data && data.error, data && data.detail);
      if (data === null) throw new ApiError('server', res.status, 'bad_response');   // 200 sem corpo nunca é sucesso
      return data;
    } catch (e) {
      if (e instanceof ApiError && e.kind === 'auth') throw e;   // a 401 propaga como 'auth' (a sessão já foi encerrada)
      if (this.revoked) throw new ApiError('revoked', 0, 'session_ended');
      if (e instanceof ApiError) throw e;
      throw new ApiError(timedOut ? 'timeout' : 'network');
    } finally { clearTimeout(timer); this.inflight.delete(ctl); }
  }
  get(path) { return this.request(path); }
  post(path, body) { return this.request(path, { method: 'POST', body }); }
}

// Logout no Supabase (melhor esforço): invalida a sessão no Auth, então o token velho deixa de passar na
// verificação do servidor (após o cache de até 60 s). DEV/LOCAL não tem o que invalidar.
export function remoteLogout(envKey, token) {
  const env = ENVIRONMENTS[envKey];
  if (!env || env.auth !== 'supabase' || !token) return;
  try { fetch(SUPABASE.url + '/auth/v1/logout?scope=local', { method: 'POST', credentials: 'omit', keepalive: true, headers: { apikey: SUPABASE.publishableKey, Authorization: 'Bearer ' + token } }).catch(() => {}); } catch { /* ignore */ }
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
