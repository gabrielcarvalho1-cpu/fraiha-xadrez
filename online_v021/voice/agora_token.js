'use strict';
// FRAIHA Voice · token RTC da Agora (AccessToken2, prefixo "007"), gerado SÓ no servidor.
// Implementação mínima do formato oficial (agora-token 2.0.x · RtcTokenBuilder2.buildTokenWithUid),
// sem dependência de runtime: crypto (HMAC-SHA256) + zlib (deflate). Conferido byte a byte contra
// o pacote oficial em tests/server/voice_token_test.cjs (com salt/issueTs fixos).
// v1 só áudio: concede JoinChannel + PublishAudio (sem vídeo, sem data stream).
const crypto = require('crypto');
const zlib = require('zlib');

const SERVICE_RTC = 1;
const PRIV_JOIN = 1, PRIV_PUB_AUDIO = 2;
const HEX32 = /^[0-9a-fA-F]{32}$/;

class Buf {
  constructor() { this.parts = []; }
  u16(v) { const b = Buffer.alloc(2); b.writeUInt16LE(v >>> 0 & 0xffff); this.parts.push(b); return this; }
  u32(v) { const b = Buffer.alloc(4); b.writeUInt32LE(v >>> 0); this.parts.push(b); return this; }
  bytes(b) { this.u16(b.length); this.parts.push(Buffer.from(b)); return this; }
  str(s) { return this.bytes(Buffer.from(String(s), 'utf8')); }
  map32(m) { const ks = Object.keys(m).map(Number).sort((a, b) => a - b); this.u16(ks.length); for (const k of ks) this.u16(k).u32(m[k]); return this; }
  pack() { return Buffer.concat(this.parts); }
}
const hmac = (key, msg) => crypto.createHmac('sha256', key).update(msg).digest();

// opts: { appId, appCertificate, channel, uid (inteiro ≥0), ttl (s), privilegeTtl (s), issueTs?, salt? }
function buildRtcAudioToken(opts) {
  const { appId, appCertificate, channel } = opts;
  if (!HEX32.test(String(appId || '')) || !HEX32.test(String(appCertificate || ''))) throw new Error('agora_config_invalid');
  if (!channel || Buffer.byteLength(channel) > 64) throw new Error('agora_channel_invalid');
  const uid = Number(opts.uid) >>> 0;
  const ttl = Math.max(1, Math.floor(Number(opts.ttl) || 600));
  const privTtl = Math.max(1, Math.floor(Number(opts.privilegeTtl) || ttl));
  const issueTs = Math.floor(opts.issueTs !== undefined ? opts.issueTs : Date.now() / 1000);
  const salt = opts.salt !== undefined ? opts.salt : crypto.randomInt(1, 99999999);
  const service = new Buf().u16(SERVICE_RTC).map32({ [PRIV_JOIN]: privTtl, [PRIV_PUB_AUDIO]: privTtl })
    .str(channel).str(uid === 0 ? '' : String(uid)).pack();
  const signingInfo = Buffer.concat([new Buf().str(appId).u32(issueTs).u32(ttl).u32(salt).u16(1).pack(), service]);
  let signing = hmac(new Buf().u32(issueTs).pack(), appCertificate);
  signing = hmac(new Buf().u32(salt).pack(), signing);
  const signature = hmac(signing, signingInfo);
  const content = Buffer.concat([new Buf().bytes(signature).pack(), signingInfo]);
  return '007' + zlib.deflateSync(content).toString('base64');
}

module.exports = { buildRtcAudioToken };
