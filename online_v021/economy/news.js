'use strict';
// R161 · NOVIDADES. O dono publica no Admin → Novidades:
//   - itens das abas ATUALIZAÇÕES / NOTÍCIAS / CAMPEONATOS / EVENTOS (título, texto, botão opcional, destaque);
//   - frases do OUTDOOR da Home (kind 'banner'), a faixa embaixo da logo.
// O jogo lê por HTTP público: GET /news → { items, banners } (só o publicado; cache de 30 s; CORS liberado,
// convidado também vê). Sem a tabela (0022): { items: [], banners: [] } e o jogo mostra a frase da arte.
const missing = e => /42P01|42703|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const KINDS = ['atualizacao', 'noticia', 'campeonato', 'evento', 'banner'];
const ACTIONS = ['', 'torneios', 'ranking', 'loja', 'premium', 'loja_coroas'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CACHE_MS = 30e3;

class News {
  constructor({ backend, now = () => Date.now() }) {
    this.backend = backend; this.now = now; this.cache = null; this.cacheAt = 0; this.offUntil = 0;
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.newsList) && this.offUntil <= this.now(); }
  off(e, where) { if (missing(e)) { this.offUntil = this.now() + 600e3; return true; } console.error('[novidades] ' + where, e && e.message); return false; }

  // ---------- público (jogo) ----------
  static publicView(rows, now = Date.now()) {
    const live = rows.filter(r => r.published && Date.parse(r.published_at || 0) <= now + 60e3);
    const items = live.filter(r => r.kind !== 'banner')
      .sort((a, b) => (b.pinned === true) - (a.pinned === true) || String(b.published_at).localeCompare(String(a.published_at)))
      .slice(0, 80)
      .map(r => ({ id: r.id, kind: r.kind, title: r.title, body: r.body || '', published_at: r.published_at, pinned: !!r.pinned,
        button_label: r.button_label || '', button_action: r.button_action || '' }));
    const banners = live.filter(r => r.kind === 'banner')
      .sort((a, b) => (b.pinned === true) - (a.pinned === true) || String(b.published_at).localeCompare(String(a.published_at)))
      .slice(0, 6).map(r => r.title);
    return { items, banners };
  }
  async publicFeed() {
    const t = this.now();
    if (this.cache && t - this.cacheAt < CACHE_MS) return this.cache;
    let out = { items: [], banners: [] };
    if (this.ok()) {
      try { out = News.publicView(await this.store.newsList(), t); }
      catch (e) { if (!this.off(e, 'feed')) { if (this.cache) return this.cache; } }
    }
    this.cache = out; this.cacheAt = t;
    return out;
  }
  // GET /news (server.js): JSON público com CORS
  async http(req, res) {
    const body = JSON.stringify(await this.publicFeed());
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*', 'cache-control': 'public, max-age=30' });
    res.end(body);
  }

  // ---------- Admin ----------
  async adminList() {
    if (!this.ok()) return { available: false, error: 'migration_0022_missing' };
    try { return { available: true, items: await this.store.newsList(), kinds: KINDS, actions: ACTIONS }; }
    catch (e) { if (this.off(e, 'admin list')) return { available: false, error: 'migration_0022_missing' }; throw e; }
  }
  static validate(b, cur) {
    const pick = (k, d) => (b[k] !== undefined ? b[k] : (cur ? cur[k] : d));
    const kind = String(pick('kind', 'noticia'));
    const title = String(pick('title', '')).trim();
    const body = String(pick('body', '')).replace(/\r\n/g, '\n').trim();
    const button_label = String(pick('button_label', '')).trim();
    const button_action = String(pick('button_action', '')).trim();
    const pinned = !!pick('pinned', false);
    const published = pick('published', true) !== false;
    let published_at = pick('published_at', null);
    if (!KINDS.includes(kind)) return { error: 'invalid_kind' };
    if (title.length < 2 || title.length > 90) return { error: 'invalid_title' };
    if (body.length > 4000) return { error: 'invalid_body' };
    if (button_label.length > 30) return { error: 'invalid_button' };
    if (button_action && !ACTIONS.includes(button_action) && !/^https:\/\/[^\s]{4,290}$/.test(button_action)) return { error: 'invalid_action' };
    if (button_label && !button_action) return { error: 'invalid_action' };
    if (published_at && isNaN(Date.parse(published_at))) return { error: 'invalid_date' };
    published_at = published_at ? new Date(published_at).toISOString() : new Date().toISOString();
    return { value: { kind, title, body: kind === 'banner' ? '' : body, button_label: kind === 'banner' ? '' : button_label,
      button_action: kind === 'banner' ? '' : button_action, pinned, published, published_at } };
  }
  async adminSave(id, b) {
    if (!this.ok()) return { status: 503, body: { error: 'migration_0022_missing' } };
    if (id && !UUID.test(id)) return { status: 400, body: { error: 'bad_id' } };
    try {
      const cur = id ? await this.store.newsGet(id) : null;
      if (id && !cur) return { status: 404, body: { error: 'not_found' } };
      const v = News.validate(b || {}, cur);
      if (v.error) return { status: 400, body: { error: v.error } };
      const row = await this.store.newsSave(cur ? { ...v.value, id: cur.id } : v.value);
      this.cache = null;
      return { status: 200, body: { item: row }, before: cur, after: row };
    } catch (e) { if (this.off(e, 'admin save')) return { status: 503, body: { error: 'migration_0022_missing' } }; throw e; }
  }
  async adminDelete(id) {
    if (!this.ok()) return { status: 503, body: { error: 'migration_0022_missing' } };
    if (!UUID.test(String(id || ''))) return { status: 400, body: { error: 'bad_id' } };
    try {
      const cur = await this.store.newsGet(id);
      if (!cur) return { status: 404, body: { error: 'not_found' } };
      await this.store.newsDelete(id);
      this.cache = null;
      return { status: 200, body: { deleted: id }, before: cur, after: null };
    } catch (e) { if (this.off(e, 'admin delete')) return { status: 503, body: { error: 'migration_0022_missing' } }; throw e; }
  }
}
module.exports = { News, KINDS, ACTIONS };
