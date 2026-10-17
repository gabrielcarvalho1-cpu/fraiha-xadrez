'use strict';
// R143 · VAGAS DO CHALLENGER (os melhores de cada ritmo).
//   · Para disputar a vaga: completar o Grão-Mestre (100 PL) e ter jogado nos últimos 7 dias.
//   · Número de vagas acompanha o tamanho do jogo: 1 vaga a cada 100 contas que jogaram aquele ritmo nos
//     últimos 30 dias, no mínimo 3 e no máximo 40.
//   · Vaga livre → entra o candidato com mais Força. Vagas cheias → o candidato mais forte toma a vaga do
//     Challenger mais fraco (menos PL; empate pela Força) se tiver mais Força que ele (1 troca por vez).
//   · Challenger que fica 7 dias sem jogar aquele ritmo, ou perde com 0 PL (progression.js), volta ao
//     Grão-Mestre (100 PL, já candidato de novo).
//   · Nunca mexe em quem está em fila, em partida ou com resultado sendo gravado (o banco recusaria a partida).
const { MODES } = require('./config');
const { forcaOf, TOP, GM } = require('./progression');
const SLOT_MAX = 40, SLOT_MIN = 3, PER_ACTIVE = 100, IDLE_MS = 7 * 86400000;

const slotsFor = active => Math.min(SLOT_MAX, Math.max(SLOT_MIN, Math.floor((active | 0) / PER_ACTIVE)));
const forcaRow = r => forcaOf({ forca: r.forca, league: r.league, pl: r.pl, matches: r.matches || 1 }).f;
const recent = (r, now) => new Date(r.updated_at || 0).getTime() >= now - IDLE_MS;

// Decide as mudanças de um ritmo (função pura: testável sem banco). Devolve [{user_id, from, to, why}].
function plan(rows, active, now, busy = () => false) {
  const n = slotsFor(active), moves = [];
  let chal = rows.filter(r => r.league === TOP);
  const cand = rows.filter(r => r.league === GM && r.pl >= 100 && recent(r, now) && !busy(r.user_id))
    .sort((a, b) => forcaRow(b) - forcaRow(a));
  const out = (r, why) => { moves.push({ user_id: r.user_id, from: { league: r.league, pl: r.pl }, to: { league: GM, pl: 100 }, why }); chal = chal.filter(x => x !== r); };
  for (const r of [...chal]) if (!recent(r, now) && !busy(r.user_id)) out(r, 'inativo');
  // ordem do Challenger: PL, depois Força (o último é o mais fraco)
  const order = () => chal.sort((a, b) => (b.pl - a.pl) || (forcaRow(b) - forcaRow(a)));
  order();
  while (chal.length > n) { const w = [...chal].reverse().find(r => !busy(r.user_id)); if (!w) break; out(w, 'menos_vagas'); }
  for (const c of cand) {
    if (chal.length < n) { moves.push({ user_id: c.user_id, from: { league: GM, pl: c.pl }, to: { league: TOP, pl: 0 }, why: 'vaga' }); chal.push({ ...c, league: TOP, pl: 0 }); continue; }
    order();
    const weakest = [...chal].reverse().find(r => !busy(r.user_id) && !r._new);
    if (weakest && forcaRow(c) > forcaRow(weakest)) {
      out(weakest, 'superado');
      moves.push({ user_id: c.user_id, from: { league: GM, pl: c.pl }, to: { league: TOP, pl: 0 }, why: 'superou' });
      chal.push({ ...c, league: TOP, pl: 0, _new: true });
    }
    break;   // no máximo 1 troca por rodada (sem vai-e-volta)
  }
  return { slots: n, moves };
}

class ChallengerLadder {
  constructor(service, { everyMs = 5 * 60000, log = console } = {}) {
    this.service = service; this.log = log; this.slots = {}; this.running = new Set();
    this.timer = setInterval(() => this.syncAll(), everyMs); this.timer.unref && this.timer.unref();
  }
  store() { return this.service.backend && this.service.backend.store; }
  busy(uid) {
    const s = this.service;
    return !!(s.activeMatchOf(uid) || s.persistPending(uid) || s.mm.has(uid) || s.pendingQueues.has(uid));
  }
  async sync(mode) {
    const st = this.store();
    if (!st || !st.challengerRows || !st.setRankedPlace || this.running.has(mode)) return null;
    this.running.add(mode);
    try {
      const { rows, active } = await st.challengerRows(mode);
      const p = plan(rows, active, Date.now(), uid => this.busy(uid));
      this.slots[mode] = p.slots;
      for (const m of p.moves) {
        const ok = await st.setRankedPlace(m.user_id, mode, m.from, m.to).catch(e => { this.log.error('challenger move failed', mode, m.user_id, e && e.message); return false; });
        if (ok) this.log.log('[challenger]', mode, m.why, m.user_id, JSON.stringify(m.from), '->', JSON.stringify(m.to));
      }
      return p;
    } catch (e) { this.log.error('challenger sync failed', mode, e && e.message); return null; }
    finally { this.running.delete(mode); }
  }
  syncAll() { for (const m of Object.keys(MODES)) void this.sync(m); }
  stop() { clearInterval(this.timer); }
}
module.exports = { ChallengerLadder, plan, slotsFor, SLOT_MAX, SLOT_MIN, PER_ACTIVE, IDLE_MS };
