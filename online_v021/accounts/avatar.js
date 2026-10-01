'use strict';
// Foto de perfil: validação do upload (0004). O cliente envia base64 de um WebP/PNG/JPEG
// já recortado para 512x512 e comprimido; aqui conferimos tamanho, tipo real (assinatura)
// e dimensões antes de gravar no Storage. Nunca confiamos no nome/mime informado.
const MAX_BYTES = 400 * 1024;      // 400 KB (bucket limita em 512 KB)
const SIZE = 512;

function sniff(bytes) {
  if (bytes.length > 12 && bytes.slice(0, 4).toString('ascii') === 'RIFF' && bytes.slice(8, 12).toString('ascii') === 'WEBP') return 'image/webp';
  if (bytes.length > 8 && bytes[0] === 0x89 && bytes.slice(1, 4).toString('ascii') === 'PNG') return 'image/png';
  if (bytes.length > 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return 'image/jpeg';
  return '';
}
// Dimensões sem decodificar a imagem inteira (só cabeçalhos).
function dimensions(bytes, mime) {
  if (mime === 'image/png') return { w: bytes.readUInt32BE(16), h: bytes.readUInt32BE(20) };
  if (mime === 'image/webp') {
    const tag = bytes.slice(12, 16).toString('ascii');
    if (tag === 'VP8X') return { w: 1 + bytes.readUIntLE(24, 3), h: 1 + bytes.readUIntLE(27, 3) };
    if (tag === 'VP8L') { const b = bytes.readUInt32LE(21); return { w: 1 + (b & 0x3FFF), h: 1 + ((b >> 14) & 0x3FFF) }; }
    if (tag === 'VP8 ') return { w: bytes.readUInt16LE(26) & 0x3FFF, h: bytes.readUInt16LE(28) & 0x3FFF };
    return null;
  }
  if (mime === 'image/jpeg') {
    let i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] !== 0xFF) { i++; continue; }
      const marker = bytes[i + 1];
      if (marker >= 0xC0 && marker <= 0xCF && marker !== 0xC4 && marker !== 0xC8 && marker !== 0xCC) return { h: bytes.readUInt16BE(i + 5), w: bytes.readUInt16BE(i + 7) };
      i += 2 + bytes.readUInt16BE(i + 2);
    }
  }
  return null;
}

function validateAvatarUpload(b64) {
  if (typeof b64 !== 'string' || !b64) return { error: 'Imagem vazia.' };
  if (b64.length > MAX_BYTES * 1.4) return { error: 'Imagem grande demais (máximo 400 KB após o recorte).' };
  let bytes;
  try { bytes = Buffer.from(b64, 'base64'); } catch (e) { return { error: 'Imagem inválida.' }; }
  if (!bytes.length || bytes.length > MAX_BYTES) return { error: 'Imagem grande demais (máximo 400 KB após o recorte).' };
  const mime = sniff(bytes);
  if (!mime) return { error: 'Formato não aceito. Use PNG, JPG ou WebP.' };
  const dim = dimensions(bytes, mime);
  if (!dim || dim.w !== SIZE || dim.h !== SIZE) return { error: 'A foto precisa ter 512x512 (recorte feito no jogo).' };
  return { bytes, mime };
}

module.exports = { validateAvatarUpload, sniff, dimensions, MAX_BYTES, SIZE };
