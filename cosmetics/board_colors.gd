extends RefCounted
## R139 · TABULEIRO E PEÇAS — padrão único da Madeira para todas as partidas; o jogador só troca as CORES
## (a arte das casas e das peças não muda). Aprovado pelo dono (prévia "opcoes_cores").
##   • grátis: algumas cores de casas e de peças + as Peças Clássicas
##   • ligas: cada liga conquistada no Ranked libera a cor de tabuleiro dela
##   • Fundador / Club: tabuleiro + peças exclusivos (substituem os antigos "universos")
## Casas: shader cosmetics/board_colors.gdshader sobre visual_v018/casas_madeira.png.
## Peças: cosmetics/cores_pecas/<id>/ (geradas por tools/art/cores_madeira_r139.py).

## escolha que vale agora (já sem o que estiver bloqueado) — atualizada pelo hub; lida por quem não tem o hub
## à mão (tabuleiro da ANÁLISE e do TREINO)
static var current_board := "madeira"
static var current_pieces := "original"

const MADEIRA := "madeira"
const ORIGINAL := "original"
const CLASSICAS := "classicas"

## id, nome, casa clara, casa escura, liberação ("" = grátis · id da liga · "founder" · "club")
const BOARDS := [
	["madeira", "Madeira", "", "", ""],
	["classico", "Clássico", "#f0d9b5", "#b58863", ""],
	["verde", "Verde", "#eeeed2", "#769656", ""],
	["azul", "Azul", "#dee3e6", "#8ca2ad", ""],
	["preto_branco", "Preto e branco", "#ececec", "#6e6e6e", ""],
	["ferro", "Ferro", "#c9ccd0", "#5d646d", "ferro"],
	["bronze", "Bronze", "#ecd2b0", "#9a5f35", "bronze"],
	["prata", "Prata", "#e6ebf0", "#8796a8", "prata"],
	["ouro", "Ouro", "#f3e3b0", "#b08a2e", "ouro"],
	["platina", "Platina", "#e1f1f4", "#5f97a6", "platina"],
	["esmeralda", "Esmeralda", "#e2efd9", "#2f7a52", "esmeralda"],
	["diamante", "Diamante", "#e3ecfb", "#3c63b8", "diamante"],
	["mestre", "Mestre", "#ece3f6", "#6d4aa0", "mestre"],
	["grande_mestre", "Grande Mestre", "#f4e1df", "#9b2f34", "grande_mestre"],
	["challenger", "Challenger", "#e9eaf6", "#46519a", "challenger"],   # escura mais clara que a prévia: peças escuras se destacam
	["fundador", "Fundador", "#f1e4bf", "#7a5a32", "founder"],          # idem
	["club", "Club", "#e7f0e2", "#1f5a43", "club"],
]

## id, nome, cor das brancas, cor das pretas, liberação
## R176.8 · o dono tirou Branco e preto / Creme e marrom / Branco e azul / Branco e vermelho (arte "suja");
## quem tinha uma delas escolhida volta para Marfim e ardósia (piece_set cai no primeiro).
const PIECES := [
	["original", "Marfim e ardósia", "", "", ""],
	["classicas", "Peças clássicas", "", "", ""],
	["fundador", "Fundador", "#f6e7b8", "#1d1a17", "founder"],
	["club", "Club", "#f2efe2", "#123a2c", "club"],
]

## luz das casas da arte (3%, mediana, 97%) — medida por tools/art/cores_madeira_r139.py
const STATS_LIGHT := Vector3(0.6315, 0.6688, 0.6904)
const STATS_DARK := Vector3(0.332, 0.3672, 0.4393)

const CASAS_PATH := "res://visual_v018/casas_madeira.png"
const SHADER_PATH := "res://cosmetics/board_colors.gdshader"
const PIECE_FILES := {
	"wP": "peao_branco", "wR": "torre_branca", "wN": "cavalo_branco", "wB": "bispo_branco", "wQ": "dama_branca", "wK": "rei_branco",
	"bP": "peao_preto", "bR": "torre_preta", "bN": "cavalo_preto", "bB": "bispo_preto", "bQ": "dama_preta", "bK": "rei_preto",
}

static func board(id: String) -> Array:
	for b in BOARDS:
		if b[0] == id: return b
	return BOARDS[0]

static func piece_set(id: String) -> Array:
	for p in PIECES:
		if p[0] == id: return p
	return PIECES[0]

## "" quando liberado; senão o texto do requisito ("Conquiste a Liga Ouro no Ranked", "Exclusivo do Club FRAIHA"…)
static func lock_reason(unlock: String, hub) -> String:
	if unlock.is_empty(): return ""
	if unlock == "founder":
		return "" if hub != null and hub.has_method("is_founder") and hub.is_founder() else "Exclusivo do Pacote Fundador"
	if unlock == "club":
		return "" if hub != null and hub.has_method("club_active") and hub.club_active() else "Exclusivo do Club FRAIHA"
	if hub != null and hub.has_method("league_unlocked") and hub.league_unlocked(unlock): return ""
	return "Conquiste a Liga %s no Ranked" % _league_name(unlock)

static func _league_name(id: String) -> String:
	var names := {"madeira": "Madeira", "ferro": "Ferro", "bronze": "Bronze", "prata": "Prata", "ouro": "Ouro", "platina": "Platina",
		"esmeralda": "Esmeralda", "diamante": "Diamante", "mestre": "Mestre", "grande_mestre": "Grande Mestre", "challenger": "Challenger"}
	return String(names.get(id, id))

static func board_unlocked(id: String, hub) -> bool:
	return lock_reason(String(board(id)[4]), hub).is_empty()

static func pieces_unlocked(id: String, hub) -> bool:
	return lock_reason(String(piece_set(id)[4]), hub).is_empty()

## Material das casas (null = Madeira original, a arte de sempre)
static var _mats := {}
static func board_material(id: String) -> ShaderMaterial:
	var b := board(id)
	if String(b[2]).is_empty(): return null
	if _mats.has(id): return _mats[id]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	m.set_shader_parameter("light_color", Color(String(b[2])))
	m.set_shader_parameter("dark_color", Color(String(b[3])))
	m.set_shader_parameter("stats_light", STATS_LIGHT)
	m.set_shader_parameter("stats_dark", STATS_DARK)
	_mats[id] = m
	return m

## guardada: quem desenha com draw_texture_* não segura a textura; se ela sair da memória entre o desenho e a
## tela, a casa sai lisa (branca no shader)
static var _casas: Texture2D = null
static func casas() -> Texture2D:
	if _casas == null: _casas = load(CASAS_PATH)
	return _casas

## Peças: dict code -> [Texture2D, Rect2] no formato do piece_override do tabuleiro, a partir das peças da Madeira
## (base) com a cor escolhida. {} = usa a base sem mudar. "classicas" é tratado por quem chama.
static var _piece_cache := {}
static func pieces(id: String, base: Dictionary) -> Dictionary:
	var p := piece_set(id)
	if String(p[2]).is_empty(): return base
	if _piece_cache.has(id): return _piece_cache[id]
	var out := {}
	for code in base:
		var path := "res://cosmetics/cores_pecas/%s/%s.png" % [id, PIECE_FILES[code]]
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		out[code] = [tex if tex != null else base[code][0], base[code][1]]
	_piece_cache[id] = out   # todos ficam (são pequenos): liberar no meio do quadro deixava a peça em branco
	return out
