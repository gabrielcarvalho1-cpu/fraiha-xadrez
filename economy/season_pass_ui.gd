extends "res://ui_v022/home_modal.gd"
## R120 · PASSE DA TEMPORADA — 30 níveis por mês; faixa GRÁTIS e faixa CLUB. Recompensas chegam sozinhas ao subir
## de nível (o servidor entrega). Aqui: nível, barra de XP, tempo até acabar, como ganhar XP e a trilha de níveis.
const CROWN := preload("res://ui_kit/mobile/bots_crown.png")
const Art := preload("res://monetization/premium_art.gd")
const BLUE := Color("bcd4ff")

var client
var head: VBoxContainer
var scroll: ScrollContainer
var track: VBoxContainer
var state: Dictionary = {}

func setup(p_hub, acc, p_client):
	build(p_hub, "PASSE DA TEMPORADA")
	account = acc
	client = p_client
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
	head = VBoxContainer.new()
	head.name = "PassHead"
	head.add_theme_constant_override("separation", 6)
	body.add_child(head)
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	track = VBoxContainer.new()
	track.name = "PassTrack"
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.add_theme_constant_override("separation", 6)
	scroll.add_child(track)

func show_pass():
	open()
	_render()
	if account != null and account.has_method("send_server"): account.send_server({"type": "pass_get"})

func _on_message(m: Dictionary):
	var t := String(m.get("type", ""))
	if t == "pass_state":
		state = m
		if visible: _render()
	elif t == "crowns_reward" and visible:
		for l in m.get("lines", []):
			if String(l).begins_with("Passe"):
				account.send_server({"type": "pass_get"})
				return

func _left(secs: int) -> String:
	var d := secs / 86400
	var h := (secs % 86400) / 3600
	if d > 0: return "%d dia%s e %dh" % [d, "" if d == 1 else "s", h]
	return "%dh %02dmin" % [h, (secs % 3600) / 60]

func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _render():
	for c in head.get_children(): c.queue_free()
	for c in track.get_children(): c.queue_free()
	if state.is_empty():
		head.add_child(_wrap(label("Abrindo o passe…", 16, CREAM, true)))
		return
	if not bool(state.get("available", false)):
		head.add_child(_wrap(label("O Passe da Temporada ainda não está ligado neste servidor. Volte em breve!", 16, CREAM, true)))
		return
	var levels := int(state.get("levels", 30))
	var per := int(state.get("xp_per_level", 150))
	var xp := int(state.get("xp", 0))
	var level := int(state.get("level", 0))
	var club := bool(state.get("club", false))
	var top: BoxContainer = VBoxContainer.new() if narrow() else HBoxContainer.new()   # celular: nome e nível em linhas
	top.add_theme_constant_override("separation", 2 if narrow() else 12)
	head.add_child(top)
	var name_l := label(String(state.get("name", "")).to_upper(), 17 if narrow() else 24, GOLD)
	name_l.name = "PassName"
	name_l.clip_text = true
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var lv := label("NÍVEL %d/%d" % [level, levels], 18 if narrow() else 22, GOLD)
	lv.name = "PassLevel"
	top.add_child(lv)
	var bar := ProgressBar.new()
	bar.name = "PassXp"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, ts(14))
	bar.max_value = per
	bar.value = per if level >= levels else (xp - level * per)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = Color("6b5428")
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e2b24f")
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	head.add_child(bar)
	var r: Dictionary = state.get("xp_rules", {}) if state.get("xp_rules") is Dictionary else {}
	var sub := "%s XP para o próximo nível · termina em %s" % ["—" if level >= levels else str((level + 1) * per - xp), _left(int(state.get("ends_in_s", 0)))]
	head.add_child(_wrap(label(sub, 13, CREAM, true)))
	head.add_child(_wrap(label("XP: vitória online %d · partida online %d · missão do dia %d · entrada do dia %d" % [int(r.get("win", 30)), int(r.get("play", 10)), int(r.get("mission", 50)), int(r.get("daily", 20))], 12, DIM, true)))
	var cl := label(("FAIXA CLUB ATIVA — você recebe as duas faixas." if club else "FAIXA CLUB: assine o Club FRAIHA e receba também a faixa Club (inclusive dos níveis que já alcançou)."), 13, BLUE if club else DIM, true)
	cl.name = "PassClubNote"
	head.add_child(_wrap(cl))
	if not club and hub.has_method("open_premium"):
		var b := button("CONHECER O CLUB", 13, true)
		b.name = "PassClubCta"
		b.pressed.connect(func(): close(); hub.open_premium("club"))
		head.add_child(b)
	# cabeçalho das colunas (fora da rolagem: sempre visível)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	head.add_child(hr)
	var c0 := label("NÍVEL", 12, DIM, true)
	c0.custom_minimum_size = Vector2(ts(56) + 11, 0)
	hr.add_child(c0)
	var c1 := label("GRÁTIS", 12, DIM, true)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(c1)
	var c2 := label("CLUB", 12, BLUE, true)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(c2)
	for rw in state.get("rewards", []):
		track.add_child(_row(rw, level, club))
	# rola até o nível atual
	_scroll_to.call_deferred(level)

func _scroll_to(level: int):
	await get_tree().process_frame
	var n = track.get_node_or_null("PassLv_%d" % maxi(1, level - 1))
	if n != null: scroll.scroll_vertical = int(n.position.y)

func _reward_text(rw) -> String:
	if not (rw is Dictionary): return "—"
	if rw.has("crowns"): return "%d COROAS" % int(rw.crowns)
	return "%s: %s" % [{"emote": "EMOTE", "title": "TÍTULO", "frame": "MOLDURA", "avatar": "AVATAR"}.get(String(rw.get("kind", "")), "ITEM"), String(rw.get("name", ""))]

func _row(rw: Dictionary, level: int, club: bool) -> Control:
	var l := int(rw.get("level", 0))
	var done := l <= level
	var p := PanelContainer.new()
	p.name = "PassLv_%d" % l
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.10, 0.24, 0.92) if done else Color(0.03, 0.06, 0.14, 0.78)
	s.border_color = GOLD if l == level else (Color("c99a45") if done else Color(0.79, 0.6, 0.27, 0.35))
	s.set_border_width_all(2 if l == level else 1)
	s.set_corner_radius_all(5)
	for side in ["left", "right"]: s.set("content_margin_" + side, 10)
	for side in ["top", "bottom"]: s.set("content_margin_" + side, 6)
	p.add_theme_stylebox_override("panel", s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var n := label(str(l), 18, GOLD if done else DIM)
	n.custom_minimum_size = Vector2(ts(56), 0)
	h.add_child(n)
	var f = rw.get("free")
	var ft := label(("✓ " if done and f != null else "") + _reward_text(f) if f != null else "—", 13 if narrow() else 15, CREAM if done else DIM, true)
	ft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ft.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(ft)
	_thumb(h, f, ft)
	var c = rw.get("club")
	var item: bool = c is Dictionary and not c.has("crowns")
	var ct := label(("✓ " if done and club else "") + _reward_text(c), 13 if narrow() else 15, (BLUE if club and done else (GOLD if item else DIM)), not item)
	ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(ct)
	_thumb(h, c, ct)
	return p

## R163 · prêmio de AVATAR no Passe: mostra o retrato pequeno antes do texto
func _thumb(row: HBoxContainer, rw, before: Control):
	if not (rw is Dictionary) or String(rw.get("kind", "")) != "avatar": return
	var Cat = preload("res://profile/avatar_catalog.gd")
	var id := String(rw.get("item", ""))
	if not Cat.has_art(id): return
	var t := TextureRect.new()
	t.name = "PassAvatar_" + id
	t.texture = load(Cat.art_path(id))
	t.custom_minimum_size = Vector2(ts(44), ts(44))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# retrato em cima, nome embaixo (lado a lado o texto quebrava letra por letra no celular)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	var at := before.get_index()
	row.remove_child(before)
	row.add_child(col)
	row.move_child(col, at)
	col.add_child(t)
	col.add_child(before)
	if before is Label:
		(before as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		(before as Label).text = String(rw.get("name", "")).to_upper()
