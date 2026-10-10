// FRAIHA · Worker do site do jogo (jogar.fraihaxadrez.com) servindo o bucket R2 fraiha-xadrez-web.
// R55.5 · entrega/cache Web. PROPOSTA versionada no repo: NÃO está publicado. Publicar exige autorização.
//
// Política (ver docs/web/R55_5_CACHE_WEB.md):
//  - index.html (e "/"): Cache-Control: no-cache + ETag. O navegador SEMPRE pergunta se mudou e recebe
//    304 (poucos bytes) quando não mudou. É o único arquivo que "descobre" release novo.
//  - Arquivos com impressão digital no nome (index-e<16hex>.js/.wasm/.audio*.js, index-p<16hex>.pck,
//    index-s<16hex>.png): o nome É o conteúdo (SHA-256). Cache de 1 ano, immutable: reload nem pergunta.
//    Release novo = nome novo; HTML novo nunca aponta para PCK/WASM velho e vice-versa.
//  - Demais arquivos (ícones, engines/, voice/, legado index.*): no-cache + ETag (304 quando igual).
//  - If-None-Match / If-Modified-Since → 304 · Range → 206 (R2 onlyIf/range).
//  - Arquivo que não existe → 404 com no-store (um 404 durante o upload não fica guardado em cache).
//
// ANTES DE PUBLICAR: copie para EXTRA_HEADERS qualquer cabeçalho que o Worker ATUAL adicione
// (ex.: segurança/COOP/COEP), para não perder comportamento existente.

export const IMMUTABLE_RE = /^index-[eps][0-9a-f]{16}\.(?:js|wasm|pck|png|audio\.worklet\.js|audio\.position\.worklet\.js)$/;
export const CC_IMMUTABLE = "public, max-age=31536000, immutable";
export const CC_REVALIDATE = "no-cache";
export const EXTRA_HEADERS = {};
// Nome da ligação (binding) R2 do Worker para o bucket fraiha-xadrez-web. Ajuste se o Worker atual usar outro.
export const BUCKET_BINDING = "BUCKET";

const TYPES = {
  html: "text/html; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  mjs: "text/javascript; charset=utf-8",
  wasm: "application/wasm",
  pck: "application/octet-stream",
  png: "image/png",
  txt: "text/plain; charset=utf-8",
  json: "application/json; charset=utf-8",
};

export function objectKey(pathname) {
  let key;
  try { key = decodeURIComponent(pathname); } catch { return null; }
  key = key.replace(/^\/+/, "");
  if (key === "" || key.endsWith("/")) key += "index.html";
  if (key.split("/").some((p) => p === ".." || p === ".")) return null;
  return key;
}

export function cachePolicy(key) {
  const name = key.split("/").pop();
  return !key.includes("/") && IMMUTABLE_RE.test(name) ? CC_IMMUTABLE : CC_REVALIDATE;
}

export function contentType(key) {
  const ext = key.split(".").pop().toLowerCase();
  return TYPES[ext] || null;
}

function baseHeaders(key) {
  const h = new Headers(EXTRA_HEADERS);
  h.set("cache-control", cachePolicy(key));
  h.set("accept-ranges", "bytes");
  h.set("x-content-type-options", "nosniff");
  return h;
}

function contentRange(range, size) {
  if (!range) return null;
  let start, end;
  if (range.suffix !== undefined) { start = Math.max(0, size - range.suffix); end = size - 1; }
  else { start = range.offset ?? 0; end = range.length !== undefined ? start + range.length - 1 : size - 1; }
  return `bytes ${start}-${end}/${size}`;
}

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Método não permitido", { status: 405, headers: { allow: "GET, HEAD" } });
    }
    const key = objectKey(new URL(request.url).pathname);
    if (key === null) return new Response("Requisição inválida", { status: 400 });
    const bucket = env[BUCKET_BINDING];
    if (!bucket) return new Response("Bucket não configurado", { status: 500, headers: { "cache-control": "no-store" } });
    const wantsRange = request.method === "GET" && request.headers.has("range");
    const obj = request.method === "HEAD"
      ? await bucket.head(key)
      : await bucket.get(key, { onlyIf: request.headers, range: wantsRange ? request.headers : undefined });
    if (obj === null) {
      return new Response("Não encontrado", { status: 404, headers: { "cache-control": "no-store", "content-type": "text/plain; charset=utf-8" } });
    }
    const h = baseHeaders(key);
    obj.writeHttpMetadata(h);
    h.set("cache-control", cachePolicy(key));            // a política vale mais que o metadado do upload
    const ct = contentType(key);
    if (ct) h.set("content-type", ct);
    h.set("etag", obj.httpEtag);
    if (obj.uploaded) h.set("last-modified", new Date(obj.uploaded).toUTCString());
    if (request.method === "HEAD") {
      h.set("content-length", String(obj.size));
      return new Response(null, { status: 200, headers: h });
    }
    if (!("body" in obj) || obj.body === null || obj.body === undefined) {
      // pré-condição falhou: If-None-Match/If-Modified-Since → 304; If-Match/If-Unmodified-Since → 412
      const notModified = request.headers.has("if-none-match") || request.headers.has("if-modified-since");
      return new Response(null, { status: notModified ? 304 : 412, headers: h });
    }
    // Content-Length explícito: o cache local do PCK (index.html) só guarda resposta com o tamanho certo.
    if (wantsRange && obj.range) {
      const cr = contentRange(obj.range, obj.size);
      const [a, b] = cr.slice(6).split("/")[0].split("-").map(Number);
      h.set("content-range", cr);
      h.set("content-length", String(b - a + 1));
      return new Response(obj.body, { status: 206, headers: h });
    }
    h.set("content-length", String(obj.size));
    return new Response(obj.body, { status: 200, headers: h });
  },
};
