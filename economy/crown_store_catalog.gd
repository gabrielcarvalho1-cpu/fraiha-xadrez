extends RefCounted
## R116 · Catálogo da LOJA DE COROAS no cliente (nomes e preços para mostrar). A fonte da verdade dos preços é o
## servidor (online_v021/economy/store_catalog.js); tests/server/loja_coroas_r116_test.cjs confere que os dois batem.
const ITEMS := [
	{"id": "estrategista", "kind": "title", "name": "Estrategista", "price": 300},
	{"id": "mestre_tatico", "kind": "title", "name": "Mestre Tático", "price": 500},
	{"id": "rei_do_blitz", "kind": "title", "name": "Rei do Blitz", "price": 600},
	{"id": "guardiao", "kind": "title", "name": "Guardião do Reino", "price": 800},
	{"id": "dama_de_ferro", "kind": "title", "name": "Dama de Ferro", "price": 800},
	{"id": "cavaleiro", "kind": "title", "name": "Cavaleiro da Coroa", "price": 1000},
	{"id": "gambito", "kind": "title", "name": "Mestre do Gambito", "price": 1000},
	{"id": "lenda_xeque", "kind": "title", "name": "Lenda do XEQUE", "price": 1200},
	{"id": "senhor_marcha", "kind": "title", "name": "Senhor da Marcha", "price": 1200},
	{"id": "imperador", "kind": "title", "name": "Imperador do Tabuleiro", "price": 1500},
	# R166 · MOLDURAS novas (arte do dono em monetization/frames/<id>.png)
	{"id": "m_safira_real", "kind": "frame", "name": "Moldura Safira Real", "price": 1000},
	{"id": "m_ametista_real", "kind": "frame", "name": "Moldura Ametista Real", "price": 1000},
	{"id": "m_esmeralda_real", "kind": "frame", "name": "Moldura Esmeralda Real", "price": 1000},
	{"id": "m_rubi_real", "kind": "frame", "name": "Moldura Rubi Real", "price": 1000},
	{"id": "m_brasa", "kind": "frame", "name": "Moldura Brasa de Lava", "price": 1500},
	{"id": "m_diamante_prata", "kind": "frame", "name": "Moldura Diamante de Prata", "price": 1500},
	{"id": "m_marmore_esmeralda", "kind": "frame", "name": "Moldura Mármore Esmeralda", "price": 1500},
	{"id": "m_diamante_dourado", "kind": "frame", "name": "Moldura Diamante Dourado", "price": 2000},
	{"id": "m_noite_estrelada", "kind": "frame", "name": "Moldura Noite Estrelada", "price": 2000},
	{"id": "m_chama_eterna", "kind": "frame", "name": "Moldura Chama Eterna", "price": 2500},
	# R163 · AVATARES da Loja (arte em profile/avatars/<id>.webp)
	{"id": "av_cavalo_dourado", "kind": "avatar", "name": "Cavalo Dourado", "price": 1000},
	{"id": "av_rainha_marmore", "kind": "avatar", "name": "Rainha de Mármore", "price": 1000},
	{"id": "av_rainha_ametista", "kind": "avatar", "name": "Rainha de Ametista", "price": 1200},
	{"id": "av_rei_rubi", "kind": "avatar", "name": "Rei de Rubi", "price": 1200},
	{"id": "av_bispo_safira", "kind": "avatar", "name": "Bispo de Safira", "price": 1200},
	{"id": "av_rei_luz", "kind": "avatar", "name": "Rei da Luz Dourada", "price": 1500},
	{"id": "av_cavaleiro_real", "kind": "avatar", "name": "Cavaleiro Real", "price": 1500},
	{"id": "av_cavaleiro_escarlate", "kind": "avatar", "name": "Cavaleiro Escarlate", "price": 1500},
	{"id": "av_guardiao_torre", "kind": "avatar", "name": "Guardião da Torre", "price": 1800},
	{"id": "av_rainha_sombria", "kind": "avatar", "name": "Rainha Sombria", "price": 2000},
	{"id": "av_tab_engrenagens", "kind": "avatar", "name": "Mesa de Engrenagens", "price": 1000},
	{"id": "av_tab_neon", "kind": "avatar", "name": "Arena Neon", "price": 1200},
	{"id": "av_tab_floresta", "kind": "avatar", "name": "Floresta Encantada", "price": 1200},
	{"id": "av_tab_ametista", "kind": "avatar", "name": "Salão de Ametista", "price": 1200},
	{"id": "av_tab_farao", "kind": "avatar", "name": "Areias do Faraó", "price": 1200},
	{"id": "av_tab_rubi", "kind": "avatar", "name": "Trono de Rubi", "price": 1500},
	{"id": "av_tab_cristal", "kind": "avatar", "name": "Palácio de Cristal", "price": 1500},
	{"id": "av_tab_vulcao", "kind": "avatar", "name": "Tabuleiro do Vulcão", "price": 1500},
	{"id": "av_tab_oceano", "kind": "avatar", "name": "Reino do Oceano", "price": 1500},
	{"id": "av_tab_astral", "kind": "avatar", "name": "Observatório Astral", "price": 1500},
	{"id": "av_rainha_violeta", "kind": "avatar", "name": "Rainha Violeta", "price": 2500},
	{"id": "av_lorde_escarlate", "kind": "avatar", "name": "Lorde Escarlate", "price": 2500},
	{"id": "av_peao_astuto", "kind": "avatar", "name": "Peão Astuto", "price": 2000},
	{"id": "av_cavaleiro_luar", "kind": "avatar", "name": "Cavaleiro do Luar", "price": 2000},
	{"id": "emote_uau", "kind": "emote", "name": "Uau!", "price": 300},
	{"id": "emote_pensando", "kind": "emote", "name": "Hmm… pensando", "price": 300},
	{"id": "emote_sorte", "kind": "emote", "name": "Que sorte!", "price": 400},
	{"id": "emote_calma", "kind": "emote", "name": "Calma, vou virar!", "price": 400},
	{"id": "emote_mate_vem", "kind": "emote", "name": "Xeque-mate chegando…", "price": 500},
	{"id": "emote_lenda", "kind": "emote", "name": "Lenda!", "price": 500},
	{"id": "emote_rei_chegou", "kind": "emote", "name": "O rei chegou!", "price": 600},
	{"id": "emote_respeito", "kind": "emote", "name": "Respeito, mestre.", "price": 600},
]

## R163 · avatares que só o PASSE entrega (não estão à venda): faixa grátis e faixa Club, nível 25, em rodízio
const PASS_AVATARS := [{"id": "av_rei_onix", "track": "free", "name": "Rei de Ônix"}, {"id": "av_rainha_onix", "track": "free", "name": "Rainha de Ônix"}, {"id": "av_torre_onix", "track": "free", "name": "Torre de Ônix"}, {"id": "av_cavalo_onix", "track": "free", "name": "Cavalo de Ônix"}, {"id": "av_principe_sombras", "track": "club", "name": "Príncipe das Sombras"}, {"id": "av_principe_esmeralda", "track": "club", "name": "Príncipe Esmeralda"}, {"id": "av_aristocrata", "track": "club", "name": "Aristocrata do Relógio"}, {"id": "av_tab_ametista_pixel", "track": "free", "name": "Ametista Pixel"}, {"id": "av_tab_gelo_pixel", "track": "free", "name": "Fortaleza de Gelo"}, {"id": "av_tab_atlantida_pixel", "track": "free", "name": "Atlântida Pixel"}, {"id": "av_tab_ruinas_pixel", "track": "free", "name": "Ruínas da Floresta"}, {"id": "av_tab_lava_pixel", "track": "free", "name": "Fortaleza de Lava"}, {"id": "av_principe_deserto", "track": "club", "name": "Príncipe do Deserto"}, {"id": "av_principe_astral", "track": "club", "name": "Príncipe Astral"}, {"id": "av_cavaleiro_prata", "track": "club", "name": "Cavaleiro de Prata"}, {"id": "av_dama_dos_bosques", "track": "free", "name": "Dama dos Bosques"}, {"id": "av_principe_estelar", "track": "club", "name": "Príncipe Estelar"}]

## R119 · emotes de graça (aparecem para todos, sem comprar)
const FREE_EMOTES := [
	{"id": "emote_ola", "text": "Olá!"},
	{"id": "emote_boa_jogada", "text": "Boa jogada!"},
	{"id": "emote_obrigado", "text": "Obrigado!"},
	{"id": "emote_boa_partida", "text": "Boa partida!"},
]

## emotes que ESTE jogador pode mandar agora: os de graça + os comprados (owned = store_state.owned)
static func my_emotes(owned: Array) -> Array:
	var out := FREE_EMOTES.duplicate()
	for it in of_kind("emote"):
		if String(it.id) in owned: out.append({"id": it.id, "text": it.name})
	return out

static func of_kind(kind: String) -> Array:
	var out := []
	for it in ITEMS:
		if String(it.kind) == kind: out.append(it)
	return out

static func item(id: String) -> Dictionary:
	for it in ITEMS:
		if String(it.id) == id: return it
	return {}

static func ids(kind: String) -> Array:
	var out := []
	for it in of_kind(kind): out.append(String(it.id))
	return out
