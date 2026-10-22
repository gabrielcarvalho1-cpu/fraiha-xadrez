extends GridContainer
## R176.8 · Galeria de EMOTES do Perfil (aba ao lado de AVATARES, ÍCONES e MOLDURAS).
## Mostra todos os emotes do chat da partida: os de graça e os comprados ficam liberados (todos podem ser usados
## no chat ao mesmo tempo, não há "aplicar"); os da Loja de Coroas aparecem com cadeado e o preço.
## Tocar só INSPECIONA (detalhe à direita, com VER NA LOJA quando bloqueado).
signal inspected(id: String)

const Shop = preload("res://economy/crown_store_catalog.gd")
const Cosmetics = preload("res://profile/premium_cosmetics.gd")
const EmoteFx = preload("res://social/emote_fx.gd")
const GOLD := Color("ffd98a")
const MUTED := Color("9c9886")
const EMERALD := Color("49d17a")

var hub
var card_size := Vector2(128, 166)
var cards := {}
var focus_id := ""

## todos os emotes, na ordem: grátis primeiro, depois os da loja (mais baratos antes)
static func all_ids() -> Array:
	var out := []
	for e in Shop.FREE_EMOTES: out.append(String(e.id))
	for it in Shop.of_kind("emote"): out.append(String(it.id))
	return out

static func text_of(id: String) -> String:
	for e in Shop.FREE_EMOTES:
		if String(e.id) == id: return String(e.text)
	return String(Shop.item(id).get("name", id))

static func price_of(id: String) -> int:
	return int(Shop.item(id).get("price", 0))

static func is_free(id: String) -> bool:
	for e in Shop.FREE_EMOTES:
		if String(e.id) == id: return true
	return false

func owned(id: String) -> bool:
	return is_free(id) or id in Cosmetics.shop_owned

## "free" | "owned" | "locked"
func state_of(id: String) -> String:
	if is_free(id): return "free"
	return "owned" if owned(id) else "locked"

func count_unlocked() -> int:
	var n := 0
	for id in cards: if owned(id): n += 1
	return n

func setup(p_hub, p_columns: int, p_card: Vector2):
	hub = p_hub
	columns = p_columns
	card_size = p_card
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 10)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	cards.clear()
	for id in all_ids():
		var card := EmoteCard.new()
		card.gallery = self
		card.emote_id = id
		card.custom_minimum_size = card_size
		card.pressed.connect(func():
			focus_id = id
			update_states()
			inspected.emit(id))
		add_child(card)
		cards[id] = card
		card.build()
	update_states()

func update_states():
	for id in cards: cards[id].refresh()

class EmoteCard extends Button:
	var gallery
	var emote_id := ""
	var fx: Control = null
	func _init():
		flat = true
		focus_mode = Control.FOCUS_ALL
		clip_contents = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
	func _ready():
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		resized.connect(_place)
	func build():
		var side := minf(custom_minimum_size.x - 40.0, custom_minimum_size.y - 80.0)
		fx = EmoteFx.make(emote_id, side)
		fx.playing = false
		add_child(fx)
		_place()
	func _place():
		if fx == null: return
		var w := maxf(size.x, custom_minimum_size.x)
		fx.position = Vector2((w - fx.size.x) / 2.0, 14)
	func refresh():
		if gallery == null: return
		var st: String = gallery.state_of(emote_id)
		if fx != null:
			fx.modulate = Color(0.45, 0.45, 0.45, 0.9) if st == "locked" else Color.WHITE
			fx.playing = gallery.focus_id == emote_id or is_hovered()
		queue_redraw()
	func _process(_d):
		if fx != null and gallery != null: fx.playing = gallery.focus_id == emote_id or is_hovered()
	func _draw():
		if gallery == null: return
		var st: String = gallery.state_of(emote_id)
		var focused: bool = gallery.focus_id == emote_id
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("161f32") if st != "locked" else Color("11151e")
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(3 if focused else 2)
		sb.border_color = Color("fff0b8") if focused else (GOLD if st != "locked" else Color("3a4038"))
		if is_hovered() or focused:
			sb.shadow_color = Color(1.0, 0.85, 0.45, 0.30)
			sb.shadow_size = 6
		draw_style_box(sb, r)
		if st == "locked":
			var lc := Vector2(size.x - 22, 22)
			draw_circle(lc, 13, Color(0, 0, 0, 0.7))
			draw_arc(lc + Vector2(0, -3), 5.0, PI, TAU, 12, Color("e6d6a8"), 2.0)
			draw_rect(Rect2(lc + Vector2(-6, -2), Vector2(12, 9)), Color("e6d6a8"))
		var font := get_theme_default_font()
		var title: String = gallery.text_of(emote_id).to_upper()
		var fs := 14
		while fs > 9 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 10: fs -= 1
		var y := size.y - 34
		draw_string(font, Vector2(5, y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, fs, GOLD if st != "locked" else MUTED)
		var sub: String = {"free": "Grátis", "owned": "Liberado", "locked": "%d coroas" % gallery.price_of(emote_id)}[st]
		draw_string(font, Vector2(5, y + 17), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 12, Color("e89a7a") if st == "locked" else (EMERALD if st == "owned" else MUTED))
		tooltip_text = title + ("  ·  Na Loja de Coroas" if st == "locked" else "")
