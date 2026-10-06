// FRAIHA Admin · configuração PÚBLICA (nada secreto aqui).
// Os servidores possíveis são FIXOS nesta lista: o Admin nunca aceita um endereço de API vindo da URL
// (evita link malicioso que mandaria seu token para outro servidor).
// Supabase: URL e chave PUBLICÁVEL — as mesmas que já vão no jogo (online.cfg). Nunca a service role.
export const ENVIRONMENTS = {
  local: { label: 'LOCAL', api: 'http://127.0.0.1:8140', auth: 'dev' },
  staging: { label: 'STAGING', api: 'https://fraiha-xadrez-staging.onrender.com', auth: 'supabase' },
  production: { label: 'PRODUCTION', api: 'https://fraiha-xadrez.onrender.com', auth: 'supabase' },
};
export const SUPABASE = { url: 'https://xbdkrrbppbhpufplnsbw.supabase.co', publishableKey: 'sb_publishable_WMG8Ha-2ahMqneRdLpv8Nw_nt8L_7Qt' };
export const REQUEST_TIMEOUT_MS = 8000;
