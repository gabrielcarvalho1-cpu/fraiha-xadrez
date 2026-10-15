extends RefCounted
## R109 · SALÃO DOS FUNDADORES — todos os Fundadores pelo número (#001, #002…), com o nome de jogador.
## Fundador Lendário aparece em destaque. Lista pública vinda do servidor (payment_founders).
const Art := preload("res://monetization/premium_art.gd")

static func build(hub, parent: VBoxContainer):
	var head := Art.Frame.new("founder", int(26 * hub.k))
	head.name = "FoundersHallHero"
	head.glow = true
	parent.add_child(head)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", int(8 * hub.k))
	head.add_child(hv)
	var crown := Art.Glyph.new("crown", 64 * hub.k, Art.GOLD, true)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hv.add_child(crown)
	var t := Art.label(hv, "SALÃO DOS FUNDADORES", hub._title_px("SALÃO DOS FUNDADORES") if hub.narrow else hub.fs(48), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.0, 0.95))
	Art.label(hv, "Quem acreditou no FRAIHA desde o começo. Cada nome fica aqui para sempre.", hub.fs(19), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
	var list: Array = hub.founders
	if not hub.founders_loaded:
		Art.label(hv, "Abrindo o salão…", hub.fs(17), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var count := Art.label(hv, ("%d FUNDADOR%s" % [list.size(), "" if list.size() == 1 else "ES"]) if list.size() > 0 else "NENHUM FUNDADOR AINDA", hub.fs(18), Color("ffe6a0"), Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
	count.name = "FoundersCount"
	if list.is_empty():
		var e := Art.label(parent, "O primeiro lugar do salão está esperando: seja o Fundador #1.", hub.fs(19), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
		e.name = "FoundersEmpty"
	else:
		var me := ""
		if hub.main_hub != null and hub.main_hub.account != null and hub.main_hub.account.profile is Dictionary:
			me = String(hub.main_hub.account.profile.get("nickname", ""))
		var grid := GridContainer.new()
		grid.name = "FoundersGrid"
		grid.columns = 2 if hub.narrow else (3 if hub.view.x < 1100.0 else 4)
		grid.add_theme_constant_override("h_separation", int(12 * hub.k))
		grid.add_theme_constant_override("v_separation", int(12 * hub.k))
		parent.add_child(grid)
		for f in list:
			grid.add_child(_tile(hub, f, String(f.get("nickname", "")) == me and not me.is_empty()))
	if hub.founder_open() and not hub.founder_owned():
		var cta := Art.Cta.new("QUERO MEU LUGAR NO SALÃO", "gold", 64 * maxf(hub.k, 0.85), int(21 * maxf(hub.k, 0.85)))
		cta.name = "HallBecomeFounder"
		cta.shimmer = true
		cta.pressed.connect(func(): hub.show_page("founder"))
		parent.add_child(cta)

static func _tile(hub, f: Dictionary, mine: bool) -> Control:
	var legend := String(f.get("tier", "")) == "legend"
	var fr := Art.Frame.new("reward" if legend or mine else "dark", int(12 * hub.k))
	fr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.glow = legend
	fr.name = "Founder_%s" % str(f.get("number", "x"))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	fr.add_child(v)
	var n = f.get("number")
	var num := Art.label(v, ("#%03d" % int(n)) if n != null else "#—", hub.fs(30), Color("fff1c0") if legend else Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	num.autowrap_mode = TextServer.AUTOWRAP_OFF
	var nick := Art.label(v, String(f.get("nickname", "")), hub.fs(18), Art.CREAM, Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
	nick.autowrap_mode = TextServer.AUTOWRAP_OFF
	nick.clip_text = true
	if legend:
		var s := Art.Stamp.new("LENDÁRIO", "new", 12)
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(s)
	elif mine:
		var s2 := Art.Stamp.new("VOCÊ", "ok", 12)
		s2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(s2)
	return fr
