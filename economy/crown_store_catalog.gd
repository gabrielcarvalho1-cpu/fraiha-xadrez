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
	{"id": "prata", "kind": "frame", "name": "Moldura de Prata", "price": 900},
	{"id": "rubi", "kind": "frame", "name": "Moldura Rubi", "price": 1200},
	{"id": "safira", "kind": "frame", "name": "Moldura Safira", "price": 1200},
	{"id": "jade", "kind": "frame", "name": "Moldura Jade", "price": 1200},
	{"id": "ametista", "kind": "frame", "name": "Moldura Ametista", "price": 1500},
	{"id": "obsidiana", "kind": "frame", "name": "Moldura Obsidiana", "price": 2000},
	{"id": "emote_uau", "kind": "emote", "name": "Uau!", "price": 300},
	{"id": "emote_pensando", "kind": "emote", "name": "Hmm… pensando", "price": 300},
	{"id": "emote_sorte", "kind": "emote", "name": "Que sorte!", "price": 400},
	{"id": "emote_calma", "kind": "emote", "name": "Calma, vou virar!", "price": 400},
	{"id": "emote_mate_vem", "kind": "emote", "name": "Xeque-mate chegando…", "price": 500},
	{"id": "emote_lenda", "kind": "emote", "name": "Lenda!", "price": 500},
	{"id": "emote_rei_chegou", "kind": "emote", "name": "O rei chegou!", "price": 600},
	{"id": "emote_respeito", "kind": "emote", "name": "Respeito, mestre.", "price": 600},
]

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
