extends SceneTree
## R176.8c · todas as frases de emote cabem na faixa (texto nunca passa da placa), em faixas pequenas e grandes.
var fails := 0
func _initialize(): call_deferred("run")
func run():
	var Shop = load("res://economy/crown_store_catalog.gd")
	var B = load("res://social/emote_banner.gd")
	var texts := []
	for e in Shop.FREE_EMOTES + Shop.PASS_EMOTES: texts.append(String(e.text))
	for it in Shop.of_kind("emote"): texts.append(String(it.name))
	for h in [44.0, 60.0, 84.0]:
		for t in texts:
			var b = B.make(t, "Gabriel", "", h)
			root.add_child(b)
			var u: float = h / 208.0
			var room: float = (B.TEXT_W * u)
			for l in b.get_children():
				if l is Label and String(l.text).replace("\n", " ") == t.to_upper():
					var f: Font = B.FONT
					var px: int = l.get_theme_font_size("font_size")
					for part in String(l.text).split("\n"):
						var tw := f.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
						if tw > room + 0.5:
							fails += 1
							print("FAIL %s (h %d): %.1f > %.1f" % [t, h, tw, room])
					var ms: Vector2 = l.get_minimum_size(); var mid: float = l.position.y + l.size.y / 2.0
					if mid - ms.y * 0.42 < 0 or mid + ms.y * 0.42 > h + 1.0:
						fails += 1
						print("FAIL altura %s (h %d) y=%.1f sz=%.1f px=%d" % [t, h, l.position.y, l.size.y, l.get_theme_font_size("font_size")])
			b.queue_free()
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
