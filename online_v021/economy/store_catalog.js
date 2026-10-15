'use strict';
// R116 · CATÁLOGO DA LOJA DE COROAS (a fonte da verdade dos PREÇOS é o servidor). Só aparência.
// O cliente tem a mesma lista com os nomes em economy/crown_store_catalog.gd (teste compara os dois).
// kind: title (texto sob o nome) | frame (moldura do retrato) | avatar | emote.
const ITEMS = [
  { id: 'estrategista', kind: 'title', name: 'Estrategista', price: 300 },
  { id: 'mestre_tatico', kind: 'title', name: 'Mestre Tático', price: 500 },
  { id: 'rei_do_blitz', kind: 'title', name: 'Rei do Blitz', price: 600 },
  { id: 'guardiao', kind: 'title', name: 'Guardião do Reino', price: 800 },
  { id: 'dama_de_ferro', kind: 'title', name: 'Dama de Ferro', price: 800 },
  { id: 'cavaleiro', kind: 'title', name: 'Cavaleiro da Coroa', price: 1000 },
  { id: 'gambito', kind: 'title', name: 'Mestre do Gambito', price: 1000 },
  { id: 'lenda_xeque', kind: 'title', name: 'Lenda do XEQUE', price: 1200 },
  { id: 'senhor_marcha', kind: 'title', name: 'Senhor da Marcha', price: 1200 },
  { id: 'imperador', kind: 'title', name: 'Imperador do Tabuleiro', price: 1500 },
  // R116 · molduras do retrato (desenho em monetization/club_frame.gd, estilo = id)
  { id: 'prata', kind: 'frame', name: 'Moldura de Prata', price: 900 },
  { id: 'rubi', kind: 'frame', name: 'Moldura Rubi', price: 1200 },
  { id: 'safira', kind: 'frame', name: 'Moldura Safira', price: 1200 },
  { id: 'jade', kind: 'frame', name: 'Moldura Jade', price: 1200 },
  { id: 'ametista', kind: 'frame', name: 'Moldura Ametista', price: 1500 },
  { id: 'obsidiana', kind: 'frame', name: 'Moldura Obsidiana', price: 2000 },
  // R119 · emotes das partidas online (o nome É o texto que aparece para o adversário)
  { id: 'emote_uau', kind: 'emote', name: 'Uau!', price: 300 },
  { id: 'emote_pensando', kind: 'emote', name: 'Hmm… pensando', price: 300 },
  { id: 'emote_sorte', kind: 'emote', name: 'Que sorte!', price: 400 },
  { id: 'emote_calma', kind: 'emote', name: 'Calma, vou virar!', price: 400 },
  { id: 'emote_mate_vem', kind: 'emote', name: 'Xeque-mate chegando…', price: 500 },
  { id: 'emote_lenda', kind: 'emote', name: 'Lenda!', price: 500 },
  { id: 'emote_rei_chegou', kind: 'emote', name: 'O rei chegou!', price: 600 },
  { id: 'emote_respeito', kind: 'emote', name: 'Respeito, mestre.', price: 600 },
];
const BY_ID = Object.fromEntries(ITEMS.map(i => [i.id, i]));
const ofKind = kind => ITEMS.filter(i => i.kind === kind).map(i => i.id);
// R119 · emotes de graça (todo jogador com conta ou convidado)
const FREE_EMOTES = [
  { id: 'emote_ola', text: 'Olá!' },
  { id: 'emote_boa_jogada', text: 'Boa jogada!' },
  { id: 'emote_obrigado', text: 'Obrigado!' },
  { id: 'emote_boa_partida', text: 'Boa partida!' },
];
const emoteText = id => { const f = FREE_EMOTES.find(e => e.id === id); if (f) return f.text; const i = BY_ID[id]; return i && i.kind === 'emote' ? i.name : null; };
const isFreeEmote = id => FREE_EMOTES.some(e => e.id === id);
module.exports = { ITEMS, BY_ID, ofKind, FREE_EMOTES, emoteText, isFreeEmote };
