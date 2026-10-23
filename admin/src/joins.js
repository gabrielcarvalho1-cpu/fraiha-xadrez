// R179 · "Entrou um jogador": o painel consulta /admin/api/joins a cada poucos segundos (em QUALQUER tela)
// e, para cada entrada nova, toca um som, mostra um aviso na tela e (se permitido) uma notificação do navegador.
// O som precisa de um clique no painel antes (regra dos navegadores): o botão 🔔 do topo libera/desliga.
import { h } from './ui.js';

const EVERY_MS = 4000;
const KEY = 'fraiha_admin_join_sound';
const LABEL = { account: 'entrou no jogo', new_account: 'CONTA NOVA criada', guest: 'convidado voltou', guest_new: 'NOVO convidado entrou' };

let ctx = null;
function audio() {
  if (!ctx) { const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return null; ctx = new AC(); }
  if (ctx.state === 'suspended') ctx.resume().catch(() => {});
  return ctx;
}
// "plim-plim" (duas notas); conta nova = três notas mais altas
function chime(kind) {
  const a = audio(); if (!a || a.state !== 'running') return;
  const notes = kind === 'new_account' ? [784, 988, 1319] : kind === 'guest_new' ? [659, 880] : [880, 1175];
  const t0 = a.currentTime + 0.02;
  notes.forEach((f, i) => {
    const o = a.createOscillator(), g = a.createGain(), t = t0 + i * 0.16;
    o.type = 'sine'; o.frequency.value = f;
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.35, t + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.5);
    o.connect(g).connect(a.destination); o.start(t); o.stop(t + 0.55);
  });
}
const readOn = () => { try { return localStorage.getItem(KEY) !== '0'; } catch { return true; } };
const saveOn = v => { try { localStorage.setItem(KEY, v ? '1' : '0'); } catch { /* sem storage */ } };

export function startJoinWatcher({ api, alive }) {
  let seq = null, timer = null, unseen = 0, on = readOn(), fails = 0;
  const baseTitle = document.title.replace(/^\(\d+\)\s*/, '');
  const btn = h('button', { class: 'btn ghost joinbell', title: 'Aviso com som quando um jogador entra no jogo' });
  const count = h('span', { class: 'joincount' }, '');
  const paint = () => {
    const ready = ctx && ctx.state === 'running';
    btn.textContent = on ? (ready ? '🔔 Som ligado' : '🔔 Clique p/ ativar som') : '🔕 Som desligado';
    btn.classList.toggle('warn', on && !ready);
  };
  let readyAtDown = false;   // estado do som ANTES deste clique (o pointerdown abaixo já libera o áudio)
  btn.onclick = () => {
    if (on && !readyAtDown) { audio(); setTimeout(() => { paint(); chime('account'); }, 120); }
    else { on = !on; saveOn(on); if (on) { audio(); setTimeout(() => { paint(); chime('account'); }, 120); } }
    if (on && 'Notification' in window && Notification.permission === 'default') Notification.requestPermission().catch(() => {});
    paint();
  };
  // qualquer clique no painel já libera o som (se estiver ligado)
  const unlock = () => { readyAtDown = !!ctx && ctx.state === 'running'; if (on) { audio(); setTimeout(paint, 120); } };
  document.addEventListener('pointerdown', unlock, { capture: true });
  const clearBadge = () => { if (!document.hidden) { unseen = 0; document.title = baseTitle; } };
  document.addEventListener('visibilitychange', clearBadge);
  const feed = h('div', { class: 'joinfeed' });
  document.body.append(feed);

  const pop = it => {
    const when = new Date(it.at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    const card = h('div', { class: 'joinpop ' + it.kind }, h('b', {}, it.nickname || 'Jogador'), ' ', LABEL[it.kind] || 'entrou', h('small', {}, when + (it.sid ? ' · clique para ver o que está fazendo' : '')));
    card.onclick = () => { card.remove(); if (it.sid) location.hash = '#/sessions/' + it.sid; };   // R180 · abre a linha do tempo da visita
    feed.prepend(card);
    while (feed.children.length > 5) feed.lastChild.remove();
    setTimeout(() => card.remove(), 15000);
    if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
      try { new Notification('FRAIHA · ' + (it.nickname || 'Jogador'), { body: LABEL[it.kind] || 'entrou no jogo', tag: 'fraiha-join-' + it.seq, silent: true }); } catch { /* sem notificação */ }
    }
  };
  const tick = async () => {
    if (!alive()) return;
    try {
      const r = await api.get('/admin/api/joins' + (seq === null ? '' : '?after=' + seq));
      if (!alive()) return;
      fails = 0;
      count.textContent = `${r.online} online` + (r.guests ? ` (${r.guests} conv.)` : '');
      if (seq !== null && r.items.length) {
        const fresh = r.items.filter(i => i.seq > seq);
        fresh.forEach(pop);
        if (fresh.length && on) chime(fresh.some(i => i.kind === 'new_account') ? 'new_account' : fresh[fresh.length - 1].kind);
        if (fresh.length && document.hidden) { unseen += fresh.length; document.title = `(${unseen}) ${baseTitle}`; }
      }
      seq = r.seq;   // 1ª consulta: só marca a posição (não toca som das entradas antigas)
    } catch (e) {
      if (!alive()) return;
      fails++;
      if (e && e.kind === 'forbidden') { count.textContent = ''; btn.remove(); return; }   // sem permissão: some
    }
    if (alive()) timer = setTimeout(tick, fails ? Math.min(30000, EVERY_MS * 2 ** Math.min(3, fails)) : EVERY_MS);
  };
  paint(); tick();
  return {
    els: [count, btn],
    stop() { clearTimeout(timer); document.removeEventListener('pointerdown', unlock, { capture: true }); document.removeEventListener('visibilitychange', clearBadge); feed.remove(); document.title = baseTitle; },
  };
}
