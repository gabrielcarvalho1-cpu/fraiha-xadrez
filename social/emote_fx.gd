extends Control
## R169 · ÍCONE ANIMADO DO EMOTE (balão grande da partida e lista de emotes): cada emote tem um desenho
## (peça dourada do FRAIHA ou símbolo do jogo) e um movimento próprio — cavalo pulando, coroa girando,
## ampulheta virando, troféu quicando… Só enfeite: não muda nada na partida.
const Art := preload("res://monetization/premium_art.gd")
const PIECES := "res://cosmetics/cores_pecas/fundador/%s.png"
## id → [peça ("cavalo_branco"…) ou "glyph:<tipo>", movimento]
const FX := {
	"emote_ola": ["peao_branco", "wave"],
	"emote_boa_jogada": ["cavalo_branco", "jump"],
	"emote_obrigado": ["glyph:heart", "pulse"],
	"emote_boa_partida": ["glyph:trophy", "bounce"],
	"emote_uau": ["glyph:gem", "spin"],
	"emote_pensando": ["glyph:hourglass", "flip"],
	"emote_sorte": ["glyph:star", "spin"],
	"emote_calma": ["glyph:shield", "shake"],
	"emote_mate_vem": ["rei_branco", "shake"],
	"emote_lenda": ["glyph:trophy", "bounce"],
	"emote_rei_chegou": ["glyph:crown", "spin"],
	"emote_respeito": ["rei_branco", "bow"],
}

var emote_id := ""
var motion := "pulse"
var art: Control
var t := 0.0
var playing := true

static func make(id: String, side: float) -> Control:
	var n = load("res://social/emote_fx.gd").new()
	n.setup(id, side)
	return n

func setup(id: String, side: float):
	emote_id = id
	name = "EmoteFx"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size
	var fx: Array = FX.get(id, ["glyph:star", "pulse"])
	motion = String(fx[1])
	var what := String(fx[0])
	if what.begins_with("glyph:"):
		art = Art.Glyph.new(what.substr(6), side * 0.86, Color("f6d27a"))
	else:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tr.texture = load(PIECES % what) if ResourceLoader.exists(PIECES % what) else null
		tr.custom_minimum_size = Vector2(side, side) * 0.9
		art = tr
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = art.custom_minimum_size
	add_child(art)
	_place(0.0)

func _process(d: float):
	if not playing or not is_visible_in_tree(): return
	t += d
	_place(t)

func _place(x: float):
	if art == null: return
	var s := size
	var base := (s - art.size) / 2.0
	art.pivot_offset = art.size / 2.0
	art.rotation = 0.0
	art.scale = Vector2.ONE
	var off := Vector2.ZERO
	match motion:
		"jump":    # cavalo: salto em arco, inclina no ar e aterrissa
			var p := fmod(x, 0.9) / 0.9
			off.y = -sin(p * PI) * s.y * 0.32
			art.rotation = sin(p * TAU) * 0.25
			if p > 0.92: art.scale = Vector2(1.08, 0.9)
		"spin":    # coroa/estrela: gira como moeda e brilha
			art.scale = Vector2(cos(x * 4.0), 1.0)
			if absf(art.scale.x) < 0.06: art.scale.x = 0.06
		"flip":    # ampulheta: vira de cabeça para baixo
			var q := fmod(x, 1.4)
			art.rotation = clampf((q - 0.9) / 0.5, 0.0, 1.0) * PI
		"bounce":
			off.y = -absf(sin(x * 5.0)) * s.y * 0.18
		"shake":
			art.rotation = sin(x * 30.0) * 0.12 * (0.6 + 0.4 * sin(x * 3.0))
		"wave":    # peão acenando
			art.rotation = sin(x * 7.0) * 0.32
		"bow":     # rei faz reverência
			var b := fmod(x, 1.6) / 1.6
			art.rotation = sin(b * PI) * 0.45
		_:         # pulse
			var k := 1.0 + 0.14 * sin(x * 7.0)
			art.scale = Vector2(k, k)
	art.position = base + off
