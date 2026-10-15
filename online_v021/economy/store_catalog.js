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
];
const BY_ID = Object.fromEntries(ITEMS.map(i => [i.id, i]));
const ofKind = kind => ITEMS.filter(i => i.kind === kind).map(i => i.id);
module.exports = { ITEMS, BY_ID, ofKind };
