extends GridContainer
## R176.9 · Galeria de TÍTULOS do Perfil (aba ao lado de AVATARES, ÍCONES, MOLDURAS e EMOTES).
## O título aparece embaixo do seu nome: no cartão do lobby, no seu perfil, no CHAT GLOBAL e para o adversário
## no início da partida — com a cor e o brilho de cada título. Tocar INSPECIONA; quem aplica é o botão do detalhe.
signal inspected(id: String)

const Cosmetics = preload("res://profile/premium_cosmetics.gd")
const Shop = preload("res://economy/crown_store_catalog.gd")
const TitleTag = preload("res://profile/title_tag.gd")
const GOLD := Color("ffd98a")
const MUTED := Color("9c9886")
const EMERALD := Color("49d17a")

var hub
var card_size := Vector2(128, 166)
var cards := {}
var focus_id := ""

## automático, sem título, os de direito (Fundador/Club) e os da Loja de Coroas
static func all_ids() -> Array:
	var out := ["auto", ""]
	for id in Cosmetics.TITLES:
		if String(id) != "": out.append(String(id))
	return out

static func display_name(id: String) -> String:
	if id == "auto": return "Automático"
	if id == "": return "Sem título"
	return Cosmetics.title_text(id)

static func price_of(id: String) -> int:
	return int(Shop.item(id).get("price", 0))

func unlocked(id: String) -> bool:
	if hub == null: return false
	if id == "auto" or id == "": return true
	return Cosmetics.allowed("title", id, hub.is_founder(), hub.club_active(), hub.is_legend() if hub.has_method("is_legend") else false)

## o que o "auto" mostra hoje
func shown(id: String) -> String:
	if id != "auto" or hub == null: return id
	return Cosmetics.effective("title", "auto", hub.is_founder(), hub.club_active(), hub.is_legend() if hub.has_method("is_legend") else false)

## "selected" | "unlocked" | "locked"
func state_of(id: String) -> String:
	if not unlocked(id): return "locked"
	return "selected" if hub != null and String(hub.cosmetic_pref("title")) == id else "unlocked"

func hint(id: String) -> String:
	return Cosmetics.lock_hint("title", id)

func count_unlocked() -> int:
	var n := 0
	for id in cards: if id != "auto" and id != "" and unlocked(id): n += 1
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
		var card := TitleCard.new()
		card.gallery = self
		card.title_id = id
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

class TitleCard extends Button:
	var gallery
	var title_id := ""
	var tag: Control = null
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
		var shown_id: String = gallery.shown(title_id)
		tag = TitleTag.make(shown_id, 18)
		tag.name = "Tag"
		add_child(tag)
		_place()
	func _place():
		if tag == null: return
		var w := maxf(size.x, custom_minimum_size.x)
		tag.size = Vector2(w - 12, 46)
		tag.position = Vector2(6, maxf(size.y, custom_minimum_size.y) * 0.36 - 23)
	func refresh():
		if gallery == null or tag == null: return
		tag.set_title(gallery.shown(title_id), 18)
		tag.glow = gallery.state_of(title_id) != "locked"
		tag.modulate = Color(0.5, 0.5, 0.5, 0.9) if gallery.state_of(title_id) == "locked" else Color.WHITE
		_place()
		queue_redraw()
	func _draw():
		if gallery == null: return
		var st: String = gallery.state_of(title_id)
		var focused: bool = gallery.focus_id == title_id
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("161f32") if st != "locked" else Color("11151e")
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(3 if st == "selected" or focused else 2)
		sb.border_color = EMERALD if st == "selected" else (Color("fff0b8") if focused else (GOLD if st == "unlocked" else Color("3a4038")))
		if st == "selected":
			sb.shadow_color = Color(0.3, 0.9, 0.5, 0.45)
			sb.shadow_size = 10
		elif is_hovered() or focused:
			sb.shadow_color = Color(1.0, 0.85, 0.45, 0.30)
			sb.shadow_size = 6
		draw_style_box(sb, r)
		var font := get_theme_default_font()
		var shown_id: String = gallery.shown(title_id)
		if shown_id == "":
			draw_string(font, Vector2(6, size.y * 0.36 + 6), "—", HORIZONTAL_ALIGNMENT_CENTER, size.x - 12, 22, MUTED)
		if st == "locked":
			var lc := Vector2(size.x - 22, 22)
			draw_circle(lc, 13, Color(0, 0, 0, 0.7))
			draw_arc(lc + Vector2(0, -3), 5.0, PI, TAU, 12, Color("e6d6a8"), 2.0)
			draw_rect(Rect2(lc + Vector2(-6, -2), Vector2(12, 9)), Color("e6d6a8"))
		var name_t: String = gallery.display_name(title_id).to_upper() if title_id in ["auto", ""] else "TÍTULO"
		var y := size.y - 34
		draw_string(font, Vector2(5, y), name_t, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 13, GOLD if st != "locked" else MUTED)
		var sub := "EM USO" if st == "selected" else ("Liberado" if st == "unlocked" else ("%d coroas" % gallery.price_of(title_id) if gallery.price_of(title_id) > 0 else "Bloqueado"))
		draw_string(font, Vector2(5, y + 17), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10, 12, EMERALD if st == "selected" else (Color("e89a7a") if st == "locked" else MUTED))
		tooltip_text = gallery.display_name(title_id) + ("  ·  " + gallery.hint(title_id) if st == "locked" else "")
