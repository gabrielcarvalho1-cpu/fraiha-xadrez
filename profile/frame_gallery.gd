extends GridContainer
## R168 · Galeria de MOLDURAS do Perfil (aba própria, ao lado de AVATARES e ÍCONES).
## Mostra todas as molduras usáveis (automática, da liga, Club, Fundador, as 11 de ELO e as da Loja de Coroas)
## com o retrato do jogador dentro. Bloqueadas em cinza com o requisito. Tocar só INSPECIONA; quem aplica é o
## botão APLICAR MOLDURA da área de detalhe (main_hub / mobile_hub).
signal inspected(id: String)

const Cosmetics = preload("res://profile/premium_cosmetics.gd")
const ClubFrame = preload("res://monetization/club_frame.gd")
const LeagueFrame = preload("res://profile/league_frame.gd")
const GOLD := Color("ffd98a")
const MUTED := Color("9c9886")
const EMERALD := Color("49d17a")

var hub
var card_size := Vector2(128, 166)
var cards := {}
var focus_id := ""

static func options() -> Array:
	var out := ["auto"]
	# R176.8 · "Da liga" saiu da galeria: para quem está na Madeira era igual ao Elo Madeira (a Automática já usa a da liga)
	for f in Cosmetics.FRAMES: if f != "liga": out.append(f)
	return out

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
	for id in options():
		var card := FrameCard.new()
		card.gallery = self
		card.frame_id = id
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

## o que a moldura "auto" mostra hoje
func shown(id: String) -> String:
	if id != "auto" or hub == null: return id
	return Cosmetics.effective("frame", "auto", hub.is_founder(), hub.club_active())

static func display_name(id: String) -> String:
	if id == "auto": return "Automática"
	return String(Cosmetics.FRAME_NAMES.get(id, id))

func unlocked(id: String) -> bool:
	if hub == null: return false
	if id == "auto": return true
	if hub.has_method("_sync_highest_league"): hub._sync_highest_league()
	return Cosmetics.allowed("frame", id, hub.is_founder(), hub.club_active())

## "selected" (é a preferência atual) | "unlocked" | "locked"
func state_of(id: String) -> String:
	if not unlocked(id): return "locked"
	var pref := String(hub.cosmetic_pref("frame")) if hub != null else ""
	if pref == "liga": pref = "auto"
	return "selected" if hub != null and pref == id else "unlocked"

func hint(id: String) -> String:
	return Cosmetics.lock_hint("frame", id)

func count_unlocked() -> int:
	var n := 0
	for id in cards: if id != "auto" and unlocked(id): n += 1
	return n

## retrato com a moldura por cima (mesmo desenho da Home/Perfil)
static func preview(hub, id: String, side: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.name = "FramePic"
	pic.texture = hub.avatar_texture() if hub != null else null
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	var fid := id
	var art: bool = fid == "liga" or ClubFrame.is_art(fid)
	# a arte sai para fora do retrato: retrato menor dentro do quadro
	var ps := side * (0.6 if art else 0.78)
	pic.size = Vector2(ps, ps)
	pic.position = Vector2((side - ps) / 2.0, (side - ps) / 2.0 + (side * 0.04 if art else 0.0))
	holder.custom_minimum_size = Vector2(side, side)
	holder.size = Vector2(side, side)
	if fid == "liga":
		var lf = LeagueFrame.new()
		lf.league_id = hub.league_profile.data.current_league if hub != null and hub.get("league_profile") != null else "madeira"
		pic.add_child(lf)
	else:
		var cf = ClubFrame.new()
		cf.style = fid
		cf.compact = false
		pic.add_child(cf)
	return holder

class FrameCard extends Button:
	var gallery
	var frame_id := ""
	var _shown := ""
	var _holder: Control = null
	func _init():
		flat = true
		clip_contents = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
	func _ready():
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		resized.connect(_place)
	func build():
		_shown = gallery.shown(frame_id)
		if _holder != null: _holder.queue_free()
		_holder = gallery.preview(gallery.hub, _shown, _side())
		_holder.name = "Preview"
		add_child(_holder)
		_place()
	func _side() -> float:
		return minf(custom_minimum_size.x - 12.0, custom_minimum_size.y - 44.0)
	func _place():
		if _holder == null: return
		var w := maxf(size.x, custom_minimum_size.x)
		_holder.position = Vector2((w - _holder.size.x) / 2.0, 4)
	func refresh():
		if gallery == null: return
		if gallery.shown(frame_id) != _shown: build()
		var st: String = gallery.state_of(frame_id)
		if _holder != null: _holder.modulate = Color(0.5, 0.5, 0.5, 0.85) if st == "locked" else Color.WHITE
		var pic = _holder.get_node_or_null("FramePic") if _holder != null else null
		if pic != null and gallery.hub != null: pic.texture = gallery.hub.avatar_texture()
		tooltip_text = gallery.display_name(frame_id).to_upper() + ("  ·  BLOQUEADO · " + gallery.hint(frame_id) if st == "locked" else "")
		queue_redraw()
	func _draw():
		if gallery == null: return
		var st: String = gallery.state_of(frame_id)
		var focused: bool = gallery.focus_id == frame_id
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
		var title: String = gallery.display_name(frame_id).to_upper().replace("MOLDURA ", "")
		var fs := 13
		while fs > 8 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 8: fs -= 1
		var y := size.y - 22
		draw_string(font, Vector2(4, y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, fs, GOLD if st != "locked" else MUTED)
		var sub: String = {"locked": "BLOQUEADO", "selected": "EM USO", "unlocked": "Disponível"}[st]
		draw_string(font, Vector2(4, y + 15), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 11, Color("e89a7a") if st == "locked" else (EMERALD if st == "selected" else MUTED))
		if st == "locked":
			var lc := Vector2(size.x - 20, 20)
			draw_circle(lc, 13, Color(0, 0, 0, 0.7))
			draw_arc(lc + Vector2(0, -3), 5.0, PI, TAU, 12, Color("e6d6a8"), 2.0)
			draw_rect(Rect2(lc + Vector2(-6, -2), Vector2(12, 9)), Color("e6d6a8"))
