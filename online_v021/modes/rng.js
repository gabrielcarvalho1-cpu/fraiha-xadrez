'use strict';
// Sorteios dos modos online. Produção: semente criptográfica por partida. Testes: semente fixa.
const crypto = require('crypto');
function rngFrom(seed) {
  let a = (seed >>> 0) || (crypto.randomBytes(4).readUInt32LE(0) >>> 0) || 1;
  const next = () => {   // mulberry32
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    float: next,
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),     // inclusivo, como randi_range
    range: (lo, hi) => lo + next() * (hi - lo),
  };
}
module.exports = { rngFrom };
