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
]

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
