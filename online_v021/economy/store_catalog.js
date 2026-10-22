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
  // R166 · molduras do retrato: pacote de arte do dono (as antigas desenhadas saíram)
  { id: 'm_noite_estrelada', kind: 'frame', name: 'Moldura Noite Estrelada', price: 10000 },
  { id: 'm_chama_eterna', kind: 'frame', name: 'Moldura Chama Eterna', price: 10000 },
  // R163 · AVATARES da Loja (o jogo tem a arte; ganha-se para sempre)
  { id: 'av_cavalo_dourado', kind: 'avatar', name: 'Cavalo Dourado', price: 1000 },
  { id: 'av_rainha_marmore', kind: 'avatar', name: 'Rainha de Mármore', price: 1000 },
  { id: 'av_rainha_ametista', kind: 'avatar', name: 'Rainha de Ametista', price: 1200 },
  { id: 'av_rei_rubi', kind: 'avatar', name: 'Rei de Rubi', price: 1200 },
  { id: 'av_bispo_safira', kind: 'avatar', name: 'Bispo de Safira', price: 1200 },
  { id: 'av_rei_luz', kind: 'avatar', name: 'Rei da Luz Dourada', price: 1500 },
  { id: 'av_cavaleiro_real', kind: 'avatar', name: 'Cavaleiro Real', price: 1500 },
  { id: 'av_cavaleiro_escarlate', kind: 'avatar', name: 'Cavaleiro Escarlate', price: 1500 },
  { id: 'av_guardiao_torre', kind: 'avatar', name: 'Guardião da Torre', price: 1800 },
  { id: 'av_rainha_sombria', kind: 'avatar', name: 'Rainha Sombria', price: 2000 },
  { id: 'av_tab_engrenagens', kind: 'avatar', name: 'Mesa de Engrenagens', price: 1000 },
  { id: 'av_tab_neon', kind: 'avatar', name: 'Arena Neon', price: 1200 },
  { id: 'av_tab_floresta', kind: 'avatar', name: 'Floresta Encantada', price: 1200 },
  { id: 'av_tab_ametista', kind: 'avatar', name: 'Salão de Ametista', price: 1200 },
  { id: 'av_tab_farao', kind: 'avatar', name: 'Areias do Faraó', price: 1200 },
  { id: 'av_tab_rubi', kind: 'avatar', name: 'Trono de Rubi', price: 1500 },
  { id: 'av_tab_cristal', kind: 'avatar', name: 'Palácio de Cristal', price: 1500 },
  { id: 'av_tab_vulcao', kind: 'avatar', name: 'Tabuleiro do Vulcão', price: 1500 },
  { id: 'av_tab_oceano', kind: 'avatar', name: 'Reino do Oceano', price: 1500 },
  { id: 'av_tab_astral', kind: 'avatar', name: 'Observatório Astral', price: 1500 },
  { id: 'av_rainha_violeta', kind: 'avatar', name: 'Rainha Violeta', price: 2500 },
  { id: 'av_lorde_escarlate', kind: 'avatar', name: 'Lorde Escarlate', price: 2500 },
  { id: 'av_peao_astuto', kind: 'avatar', name: 'Peão Astuto', price: 2000 },
  { id: 'av_cavaleiro_luar', kind: 'avatar', name: 'Cavaleiro do Luar', price: 2000 },
  // R119 · emotes das partidas online (o nome É o texto que aparece para o adversário)
  { id: 'emote_uau', kind: 'emote', name: 'Uau!', price: 300 },
  { id: 'emote_pensando', kind: 'emote', name: 'Hmm… pensando', price: 300 },
  { id: 'emote_sorte', kind: 'emote', name: 'Que sorte!', price: 400 },
  { id: 'emote_calma', kind: 'emote', name: 'Calma, vou virar!', price: 400 },
  { id: 'emote_mate_vem', kind: 'emote', name: 'Xeque-mate chegando…', price: 500 },
  { id: 'emote_lenda', kind: 'emote', name: 'Lenda!', price: 500 },
  { id: 'emote_rei_chegou', kind: 'emote', name: 'O rei chegou!', price: 600 },
  { id: 'emote_respeito', kind: 'emote', name: 'Respeito, mestre.', price: 600 },
  // R176.8 · emotes novos da Loja (sugestão do dono)
  { id: 'emote_vamos', kind: 'emote', name: 'VAMOS!', price: 300 },
  { id: 'emote_xeque', kind: 'emote', name: 'XEQUE!', price: 400 },
  { id: 'emote_interessante', kind: 'emote', name: 'INTERESSANTE...', price: 400 },
  { id: 'emote_doeu', kind: 'emote', name: 'ESSA DOEU!', price: 500 },
  { id: 'emote_de_novo', kind: 'emote', name: 'JOGAMOS DE NOVO!', price: 500 },
];
const BY_ID = Object.fromEntries(ITEMS.map(i => [i.id, i]));
// R163 · avatares que só o PASSE entrega (não estão à venda; ficam na conta como item da loja, preço 0)
const PASS_AVATARS = [{ id: 'av_rei_onix', track: 'free', name: 'Rei de Ônix' }, { id: 'av_rainha_onix', track: 'free', name: 'Rainha de Ônix' }, { id: 'av_torre_onix', track: 'free', name: 'Torre de Ônix' }, { id: 'av_cavalo_onix', track: 'free', name: 'Cavalo de Ônix' }, { id: 'av_principe_sombras', track: 'club', name: 'Príncipe das Sombras' }, { id: 'av_principe_esmeralda', track: 'club', name: 'Príncipe Esmeralda' }, { id: 'av_aristocrata', track: 'club', name: 'Aristocrata do Relógio' }, { id: 'av_tab_ametista_pixel', track: 'free', name: 'Ametista Pixel' }, { id: 'av_tab_gelo_pixel', track: 'free', name: 'Fortaleza de Gelo' }, { id: 'av_tab_atlantida_pixel', track: 'free', name: 'Atlântida Pixel' }, { id: 'av_tab_ruinas_pixel', track: 'free', name: 'Ruínas da Floresta' }, { id: 'av_tab_lava_pixel', track: 'free', name: 'Fortaleza de Lava' }, { id: 'av_principe_deserto', track: 'club', name: 'Príncipe do Deserto' }, { id: 'av_principe_astral', track: 'club', name: 'Príncipe Astral' }, { id: 'av_cavaleiro_prata', track: 'club', name: 'Cavaleiro de Prata' }, { id: 'av_dama_dos_bosques', track: 'free', name: 'Dama dos Bosques' }, { id: 'av_principe_estelar', track: 'club', name: 'Príncipe Estelar' }];
const PASS_BY_ID = Object.fromEntries(PASS_AVATARS.map(a => [a.id, a]));
// R176.8 · emotes que só o PASSE entrega (nível 10: um da faixa grátis e um da faixa Club, em rodízio por temporada)
const PASS_EMOTES = [
  { id: 'emote_quase', track: 'free', text: 'QUASE!' },
  { id: 'emote_ops', track: 'free', text: 'OPS!' },
  { id: 'emote_merecido', track: 'free', text: 'MERECIDO!' },
  { id: 'emote_que_jogada', track: 'club', text: 'QUE JOGADA!' },
  { id: 'emote_eu_vi', track: 'club', text: 'EU VI ESSA!' },
];
const ofKind = kind => ITEMS.filter(i => i.kind === kind).map(i => i.id);
// R119 · emotes de graça (todo jogador com conta ou convidado)
const FREE_EMOTES = [
  { id: 'emote_ola', text: 'Olá!' },
  { id: 'emote_boa_jogada', text: 'Boa jogada!' },
  { id: 'emote_obrigado', text: 'Obrigado!' },
  { id: 'emote_boa_partida', text: 'Boa partida!' },
  // R176.8 · novos de graça
  { id: 'emote_boa_sorte', text: 'BOA SORTE!' },
  { id: 'emote_parabens', text: 'PARABÉNS!' },
  { id: 'emote_revanche', text: 'REVANCHE?' },
];
const emoteText = id => { const f = FREE_EMOTES.find(e => e.id === id) || PASS_EMOTES.find(e => e.id === id); if (f) return f.text; const i = BY_ID[id]; return i && i.kind === 'emote' ? i.name : null; };
const isFreeEmote = id => FREE_EMOTES.some(e => e.id === id);
module.exports = { ITEMS, BY_ID, ofKind, FREE_EMOTES, emoteText, isFreeEmote, PASS_AVATARS, PASS_BY_ID, PASS_EMOTES };
