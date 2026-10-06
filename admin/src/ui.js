// FRAIHA Admin · utilitários de interface. Tudo via DOM (textContent): nenhum dado do servidor vira HTML.
export function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
    else if (k === 'dataset') Object.assign(el.dataset, v);
    else if (k === 'style') el.style.cssText = v;   // CSSOM: permitido pela CSP (atributo style não)
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const k of kids.flat(Infinity)) if (k !== null && k !== undefined && k !== false) el.append(k instanceof Node ? k : document.createTextNode(String(k)));
  return el;
}
export const fmtInt = n => (n === null || n === undefined) ? '—' : Number(n).toLocaleString('pt-BR');
export function fmtDur(ms) {
  if (ms === null || ms === undefined) return '—';
  const s = Math.round(ms / 1000); if (s < 60) return s + ' s';
  const m = Math.floor(s / 60); if (m < 60) return `${m} min ${s % 60 ? (s % 60) + ' s' : ''}`.trim();
  return `${Math.floor(m / 60)} h ${m % 60} min`;
}
export function fmtDate(iso) { if (!iso) return '—'; const d = new Date(iso); return isNaN(d) ? '—' : d.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }); }
export function fmtAgo(iso) { if (!iso) return '—'; const s = (Date.now() - new Date(iso).getTime()) / 1000; if (s < 60) return 'agora'; if (s < 3600) return Math.floor(s / 60) + ' min atrás'; if (s < 86400) return Math.floor(s / 3600) + ' h atrás'; return Math.floor(s / 86400) + ' d atrás'; }
const STATUS = { real: 'REAL', partial: 'PARCIAL', unavailable: 'SEM DADOS' };
export const statusBadge = st => h('span', { class: 'badge ' + st, title: { real: 'Dado real do servidor', partial: 'Dado real, mas incompleto (ex.: desde o último reinício)', unavailable: 'Ainda não existe no backend' }[st] || '' }, STATUS[st] || st);

// Card de métrica: NUNCA mostra número quando o servidor diz que o dado não existe.
export function metricCard(label, m, { fmt = fmtInt, hero = false } = {}) {
  const has = m && m.status !== 'unavailable' && m.value !== null && m.value !== undefined;
  return h('div', { class: 'card' + (hero ? ' hero' : ''), dataset: { metric: label, status: m ? m.status : 'unavailable' } },
    h('div', { class: 'lbl' }, h('span', {}, label), statusBadge(m ? m.status : 'unavailable')),
    has ? h('div', { class: 'val' }, fmt(m.value)) : h('div', { class: 'val na' }, m && m.status === 'unavailable' ? 'INDISPONÍVEL' : '—'),
    h('div', { class: 'note' }, m ? m.note || '' : 'sem resposta do servidor'));
}
export const unavailable = text => h('span', { class: 'unav' }, text || 'INDISPONÍVEL — BACKEND NECESSÁRIO');

export function stateBox(kind, text) { return h('div', { class: 'state' + (kind === 'error' ? ' err' : '') }, text); }
export function loadingCards(n = 4) { return h('div', { class: 'grid' }, Array.from({ length: n }, () => h('div', { class: 'card' }, h('div', { class: 'skeleton', style: 'width:50%' }), h('div', { class: 'skeleton', style: 'width:30%;height:26px;margin-top:14px' })))); }

let toastTimer;
export function toast(text, kind = 'ok') {
  document.querySelectorAll('.toast').forEach(t => t.remove());
  const t = h('div', { class: 'toast ' + kind, role: 'status' }, text); document.body.append(t);
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.remove(), 4500);
}

// Confirmação de ação sensível: exige motivo + digitar o identificador. Resolve {reason} ou null.
export function confirmAction({ title, body, confirmWord, actionLabel, danger = true }) {
  return new Promise(resolve => {
    const reason = h('textarea', { rows: 2, placeholder: 'Ex.: manutenção do servidor', maxlength: 300 });
    const word = h('input', { type: 'text', placeholder: confirmWord, autocomplete: 'off', spellcheck: 'false' });
    const go = h('button', { class: 'btn ' + (danger ? 'danger' : 'ok'), disabled: true }, actionLabel);
    const check = () => { go.disabled = !(reason.value.trim().length >= 3 && word.value.trim() === confirmWord); };
    reason.addEventListener('input', check); word.addEventListener('input', check);
    const close = v => { bg.remove(); resolve(v); };
    const bg = h('div', { class: 'modal-bg', onclick: e => { if (e.target === bg) close(null); } },
      h('div', { class: 'modal', role: 'dialog', 'aria-modal': 'true' },
        h('h3', {}, title), h('p', { class: 'muted' }, body),
        h('div', { class: 'fields' }, h('label', {}, 'Motivo (vai para o Admin Log)', reason), h('label', {}, `Digite "${confirmWord}" para confirmar`, word)),
        h('div', { class: 'actions' }, h('button', { class: 'btn ghost', onclick: () => close(null) }, 'Cancelar'), go)));
    go.addEventListener('click', () => close({ reason: reason.value.trim(), confirm: word.value.trim() }));
    document.body.append(bg); reason.focus();
  });
}

// Gráfico de linhas em SVG (sem biblioteca). series = [{at,...}], keys = [{key,label,color}]
export function lineChart(series, keys, { height = 200, empty = 'Sem amostras ainda.' } = {}) {
  const NS = 'http://www.w3.org/2000/svg';
  const wrap = h('div', {});
  if (!series || series.length < 2) { wrap.append(stateBox('empty', empty)); return wrap; }
  const W = 800, H = height, P = { l: 34, r: 10, t: 10, b: 22 };
  const t0 = series[0].at, t1 = series[series.length - 1].at || t0 + 1;
  const vmax = Math.max(1, ...series.flatMap(p => keys.map(k => Number(k.get ? k.get(p) : p[k.key]) || 0)));
  const x = t => P.l + (W - P.l - P.r) * ((t - t0) / Math.max(1, t1 - t0));
  const y = v => H - P.b - (H - P.t - P.b) * (v / vmax);
  const svg = document.createElementNS(NS, 'svg'); svg.setAttribute('viewBox', `0 0 ${W} ${H}`); svg.setAttribute('class', 'chart'); svg.setAttribute('preserveAspectRatio', 'none');
  const add = (tag, at, parent = svg) => { const e = document.createElementNS(NS, tag); for (const [k, v] of Object.entries(at)) e.setAttribute(k, v); parent.append(e); return e; };
  const g = add('g', { class: 'grid' }), ax = add('g', { class: 'axis' });
  for (let i = 0; i <= 4; i++) { const v = Math.round(vmax * i / 4); add('line', { x1: P.l, x2: W - P.r, y1: y(v), y2: y(v) }, g); add('text', { x: 4, y: y(v) + 3 }, ax).textContent = v; }
  for (const f of [0, .5, 1]) { const t = t0 + (t1 - t0) * f; add('text', { x: Math.min(W - 40, Math.max(P.l, x(t) - 16)), y: H - 6 }, ax).textContent = new Date(t).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }); }
  for (const k of keys) add('polyline', { fill: 'none', stroke: k.color, 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke', points: series.map(p => `${x(p.at).toFixed(1)},${y(Number(k.get ? k.get(p) : p[k.key]) || 0).toFixed(1)}`).join(' ') });
  wrap.append(svg, h('div', { class: 'legend' }, keys.map(k => h('span', {}, h('i', { style: `background:${k.color}` }), k.label))));
  return wrap;
}
export const FAMILY_LABEL = { ranked: 'RANKED', casual: 'CASUAL', xeque: 'XEQUE', marcha: 'MARCHA REAL' };
export const PLACE_LABEL = { offline: 'Offline', lobby: 'Home / Lobby', queue: 'Em fila', match: 'Em partida' };
