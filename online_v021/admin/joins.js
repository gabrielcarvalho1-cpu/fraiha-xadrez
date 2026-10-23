'use strict';
// R179 · "entrou um jogador": log em memória das entradas no jogo (conta, conta nova, convidado) para o Admin
// tocar um aviso sonoro. Uma entrada por jogador a cada DEDUP_MS (reconexões/troca de aba não repetem o aviso).
const MAX = 300;
const DEDUP_MS = 10 * 60e3;

class JoinLog {
  constructor({ now = () => Date.now(), dedupMs = DEDUP_MS } = {}) {
    this.now = now; this.dedupMs = dedupMs;
    this.seq = 0; this.items = []; this.last = new Map(); this.fresh = new Set();
  }
  // conta que acabou de criar o perfil: a próxima entrada dela vira "conta nova"
  markNew(uid) { if (uid) this.fresh.add(String(uid)); }
  note({ id, nickname, guest, newGuest }) {
    if (!id) return null;
    const uid = String(id), t = this.now();
    const isNew = this.fresh.delete(uid);
    const prev = this.last.get(uid);
    if (!isNew && !newGuest && prev && t - prev < this.dedupMs) return null;
    this.last.set(uid, t);
    if (this.last.size > 5000) for (const [k, v] of this.last) { if (t - v > this.dedupMs) this.last.delete(k); if (this.last.size <= 4000) break; }
    const kind = guest ? (newGuest ? 'guest_new' : 'guest') : (isNew ? 'new_account' : 'account');
    const it = { seq: ++this.seq, at: new Date(t).toISOString(), kind, nickname: String(nickname || '').slice(0, 40), guest: !!guest, uid: guest ? null : uid };
    this.items.push(it);
    if (this.items.length > MAX) this.items.splice(0, this.items.length - MAX);
    return it;
  }
  // after: último seq que o painel já viu. Sem after (ou inválido) → só devolve o seq atual + as últimas 20.
  since(after) {
    const a = Number(after);
    const list = Number.isFinite(a) && a >= 0 ? this.items.filter(i => i.seq > a) : this.items.slice(-20);
    return { seq: this.seq, items: list.slice(-50) };
  }
}
module.exports = { JoinLog };
