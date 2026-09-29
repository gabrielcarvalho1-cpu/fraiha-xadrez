'use strict';
// Port of chess/rules.gd for server-authoritative Ranked. Coordinates match the
// Godot client: x=0..7 (a..h), y=0 is Black's back rank, y=7 is White's.
const KNIGHTS = [[1,2],[2,1],[2,-1],[1,-2],[-1,-2],[-2,-1],[-2,1],[-1,2]];
const DIRS = [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]];
const K = (x, y) => x + ',' + y;
const inside = (x, y) => x >= 0 && y >= 0 && x < 8 && y < 8;
const other = c => (c === 'w' ? 'b' : 'w');

class Position {
  constructor() { this.reset(); }
  reset() {
    this.board = {};
    const back = ['R','N','B','Q','K','B','N','R'];
    for (let x = 0; x < 8; x++) {
      this.board[K(x,0)] = 'b' + back[x]; this.board[K(x,1)] = 'bP';
      this.board[K(x,6)] = 'wP'; this.board[K(x,7)] = 'w' + back[x];
    }
    this.turn = 'w'; this.rights = 'KQkq'; this.ep = null; this.halfmove = 0; this.ply = 0;
    this.repetitions = { [this.positionKey()]: 1 };
    this.history = [];
  }
  clone() {
    const p = Object.create(Position.prototype);
    p.board = { ...this.board }; p.turn = this.turn; p.rights = this.rights; p.ep = this.ep ? [...this.ep] : null;
    p.halfmove = this.halfmove; p.ply = this.ply; p.repetitions = { ...this.repetitions }; p.history = [...this.history];
    return p;
  }
  piece(x, y) { return this.board[K(x,y)] || ''; }
  attacked(x, y, by) {
    const dy = by === 'w' ? -1 : 1;
    for (const dx of [-1,1]) if (this.piece(x-dx, y-dy) === by + 'P') return true;
    for (const [a,b] of KNIGHTS) if (this.piece(x+a, y+b) === by + 'N') return true;
    for (let i = 0; i < 8; i++) {
      const [dx2, dy2] = DIRS[i]; let px = x + dx2, py = y + dy2, dist = 1;
      while (inside(px, py)) {
        const code = this.piece(px, py);
        if (code) {
          if (code[0] === by) {
            if (code[1] === 'K' && dist === 1) return true;
            if (code[1] === 'Q' || code[1] === (i < 4 ? 'R' : 'B')) return true;
          }
          break;
        }
        dist++; px += dx2; py += dy2;
      }
    }
    return false;
  }
  inCheck(c) {
    for (const k in this.board) if (this.board[k] === c + 'K') { const [x,y] = k.split(',').map(Number); return this.attacked(x, y, other(c)); }
    return true;
  }
  pseudo(fx, fy) {
    const out = [], code = this.piece(fx, fy); if (!code) return out;
    const c = code[0], kind = code[1];
    if (kind === 'P') {
      const dy = c === 'w' ? -1 : 1;
      if (inside(fx, fy+dy) && !this.piece(fx, fy+dy)) {
        out.push([fx, fy+dy]);
        if (fy === (c === 'w' ? 6 : 1) && !this.piece(fx, fy+2*dy)) out.push([fx, fy+2*dy]);
      }
      for (const dx of [-1,1]) {
        const tx = fx+dx, ty = fy+dy; if (!inside(tx, ty)) continue;
        const t = this.piece(tx, ty);
        if (t && t[0] !== c && t[1] !== 'K') out.push([tx, ty]);
        else if (!t && this.ep && this.ep[0] === tx && this.ep[1] === ty && this.piece(tx, fy) === other(c) + 'P') out.push([tx, ty]);
      }
    } else if (kind === 'N' || kind === 'K') {
      for (const [a,b] of (kind === 'N' ? KNIGHTS : DIRS)) {
        const tx = fx+a, ty = fy+b, t = this.piece(tx, ty);
        if (inside(tx, ty) && (!t || (t[0] !== c && t[1] !== 'K'))) out.push([tx, ty]);
      }
      if (kind === 'K' && fx === 4 && fy === (c === 'w' ? 7 : 0) && !this.inCheck(c)) {
        for (const side of [0,1]) {
          const sym = c === 'w' ? (side === 0 ? 'K' : 'Q') : (side === 0 ? 'k' : 'q');
          const rx = side === 0 ? 7 : 0, step = side === 0 ? 1 : -1;
          if (!this.rights.includes(sym) || this.piece(rx, fy) !== c + 'R') continue;
          const xs = side === 0 ? [5,6] : [1,2,3];
          if (xs.some(x => this.piece(x, fy))) continue;
          if (!this.attacked(fx+step, fy, other(c)) && !this.attacked(fx+2*step, fy, other(c))) out.push([fx+2*step, fy]);
        }
      }
    } else {
      for (let i = 0; i < 8; i++) {
        if (kind === 'B' && i < 4) continue; if (kind === 'R' && i >= 4) continue;
        const [dx, dy] = DIRS[i]; let tx = fx+dx, ty = fy+dy;
        while (inside(tx, ty)) {
          const t = this.piece(tx, ty);
          if (!t) out.push([tx, ty]); else { if (t[0] !== c && t[1] !== 'K') out.push([tx, ty]); break; }
          tx += dx; ty += dy;
        }
      }
    }
    return out;
  }
  legalFrom(fx, fy) {
    const code = this.piece(fx, fy); if (!code || code[0] !== this.turn) return [];
    return this.pseudo(fx, fy).filter(([tx, ty]) => {
      const p = this.clone(); p.applyUnchecked({ from:[fx,fy], to:[tx,ty], promotion:'Q' }, false);
      return !p.inCheck(code[0]);
    });
  }
  legalMoves() {
    const moves = [];
    for (const k in this.board) {
      if (this.board[k][0] !== this.turn) continue;
      const [fx, fy] = k.split(',').map(Number);
      for (const [tx, ty] of this.legalFrom(fx, fy)) {
        if (this.board[k][1] === 'P' && (ty === 0 || ty === 7)) for (const pr of ['Q','R','B','N']) moves.push({ from:[fx,fy], to:[tx,ty], promotion:pr });
        else moves.push({ from:[fx,fy], to:[tx,ty], promotion:'Q' });
      }
    }
    return moves;
  }
  // Returns the applied move description or null when illegal.
  play(move) {
    if (!move || !Array.isArray(move.from) || !Array.isArray(move.to)) return null;
    const [fx, fy] = move.from.map(Number), [tx, ty] = move.to.map(Number);
    if (![fx,fy,tx,ty].every(Number.isInteger) || !inside(fx,fy) || !inside(tx,ty)) return null;
    const promotion = String(move.promotion || 'Q');
    if (!['Q','R','B','N'].includes(promotion)) return null;
    if (!this.legalFrom(fx, fy).some(([a,b]) => a === tx && b === ty)) return null;
    const code = this.piece(fx, fy);
    const isPromotion = code[1] === 'P' && (ty === 0 || ty === 7);
    const captured = this.applyUnchecked({ from:[fx,fy], to:[tx,ty], promotion }, true);
    const uci = 'abcdefgh'[fx] + (8-fy) + 'abcdefgh'[tx] + (8-ty) + (isPromotion ? promotion.toLowerCase() : '');
    this.history.push(uci);
    return { from:[fx,fy], to:[tx,ty], piece:code, promotion: isPromotion ? promotion : '', captured, uci };
  }
  applyUnchecked(move, record) {
    const [fx, fy] = move.from, [tx, ty] = move.to, code = this.piece(fx, fy);
    let captured = this.piece(tx, ty) || '';
    let capture = !!captured;
    if (code[1] === 'P' && this.ep && this.ep[0] === tx && this.ep[1] === ty && fx !== tx && !capture) {
      captured = this.piece(tx, fy); delete this.board[K(tx, fy)]; capture = true;
    }
    for (const [sx, sy] of [[7,7],[0,7],[7,0],[0,0]]) {
      if ((fx === sx && fy === sy) || (tx === sx && ty === sy)) {
        const sym = sy === 7 ? (sx === 7 ? 'K' : 'Q') : (sx === 7 ? 'k' : 'q');
        this.rights = this.rights.replace(sym, '');
      }
    }
    if (code[1] === 'K') {
      this.rights = this.rights.replace(code[0] === 'w' ? 'K' : 'k', '').replace(code[0] === 'w' ? 'Q' : 'q', '');
      if (Math.abs(tx - fx) === 2) {
        const rx = tx > fx ? 7 : 0; delete this.board[K(rx, fy)];
        this.board[K(tx > fx ? 5 : 3, fy)] = code[0] + 'R';
      }
    }
    delete this.board[K(fx, fy)];
    this.board[K(tx, ty)] = code[1] === 'P' && (ty === 0 || ty === 7) ? code[0] + (move.promotion || 'Q') : code;
    this.ep = code[1] === 'P' && Math.abs(fy - ty) === 2 ? [fx, (fy + ty) / 2] : null;
    this.halfmove = capture || code[1] === 'P' ? 0 : this.halfmove + 1;
    this.ply++;
    this.turn = other(this.turn);
    if (record) { const k = this.positionKey(); this.repetitions[k] = (this.repetitions[k] || 0) + 1; }
    return captured;
  }
  positionKey() {
    const parts = [];
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) parts.push(this.piece(x, y));
    let eff = '';
    if (this.ep) {
      const row = this.ep[1] + (this.turn === 'w' ? 1 : -1);
      for (const dx of [-1,1]) {
        const fx = this.ep[0] + dx;
        if (this.piece(fx, row) === this.turn + 'P' && this.legalFrom(fx, row).some(([a,b]) => a === this.ep[0] && b === this.ep[1])) eff = this.ep.join(',');
      }
    }
    return parts.join(',') + '|' + this.turn + '|' + this.rights + '|' + eff;
  }
  insufficientMaterial() {
    const minors = [];
    for (const k in this.board) {
      const kind = this.board[k][1]; if ('PRQ'.includes(kind)) return false;
      if (kind !== 'K') { const [x,y] = k.split(',').map(Number); minors.push([kind, (x+y) % 2]); }
    }
    if (minors.length <= 1) return true;
    return minors.every(m => m[0] === 'B' && m[1] === minors[0][1]);
  }
  // Can `color` still deliver mate by some legal sequence? Used for flag-fall:
  // lone king, or king + one minor against a bare king, cannot win on time.
  canMate(color) {
    const own = [], opp = [];
    for (const k in this.board) { const p = this.board[k]; if (p[1] === 'K') continue; (p[0] === color ? own : opp).push(p[1]); }
    if (own.length === 0) return false;
    if (own.some(k => 'PRQ'.includes(k))) return true;
    if (own.length >= 2) {
      // Only same-coloured bishops can never mate.
      const bishops = [];
      for (const k in this.board) { const p = this.board[k]; if (p[0] === color && p[1] === 'B') { const [x,y] = k.split(',').map(Number); bishops.push((x+y)%2); } }
      if (bishops.length === own.length && bishops.every(b => b === bishops[0]) && opp.length === 0) return false;
      return true;
    }
    return opp.length > 0; // a single minor can only help-mate against blocking material
  }
  outcome() {
    if (this.legalMoves().length === 0) return this.inCheck(this.turn) ? 'checkmate' : 'stalemate';
    if (this.insufficientMaterial()) return 'insufficient_material';
    if (this.halfmove >= 100) return 'fifty_moves';
    if ((this.repetitions[this.positionKey()] || 0) >= 3) return 'repetition';
    return '';
  }
  snapshot() {
    return { board: Object.entries(this.board).map(([k,p]) => [...k.split(',').map(Number), p]), turn: this.turn,
      rights: this.rights, ep: this.ep || [-1,-1], halfmove: this.halfmove, ply: this.ply };
  }
}
module.exports = { Position, other };
