extends SceneTree
## R180 · TODAS as frases de emote na faixa, em 4 alturas (34/44/56/70 px): a frase fica dentro da placa azul
## (entre o medalhão e a borda direita), centralizada, sem cortar.
const Banner := preload("res://social/emote_banner.gd")
const Cat := preload("res://economy/crown_store_catalog.gd")
var fails := 0
func _initialize(): call_deferred("run")
func check(ok: bool, msg: String):
	if not ok:
		print("FAIL " + msg)
		fails += 1
func run():
	var size := Vector2i(1500, 1300)
	root.size = size
	root.content_scale_size = size
	var bg := ColorRect.new()
	bg.color = Color("3a2a20")
	bg.size = Vector2(size)
	root.add_child(bg)
	var items := []
	for e in Cat.FREE_EMOTES: items.append([e.id, e.text])
	for e in Cat.PASS_EMOTES: items.append([e.id, e.text])
	for e in Cat.ITEMS: if String(e.get("kind", "")) == "emote": items.append([e.id, e.name])
	var hs := [44.0, 52.0, 62.0, 84.0]
	var x := 8.0
	var col_w := [120.0, 150.0, 190.0, 230.0]
	var y := 8.0
	for it in items:
		x = 8.0
		for i in hs.size():
			var b: Control = Banner.make(String(it[1]), "", String(it[0]), hs[i])
			b.position = Vector2(x, y)
			root.add_child(b)
			x += b.size.x + 10.0
		y += 72.0
	for i in 4: await process_frame
	# confere: cada linha da frase dentro da área azul (x 216..576, y 60..168 da arte 640x208), centralizada
	for b in root.get_children():
		if b == bg: continue
		var u: float = b.size.y / 208.0
		var inner := Rect2(Vector2(216, 60) * u, Vector2(360, 108) * u)
		for r in b.phrase_rects():
			check(inner.encloses(r), "%s h=%d: %s fora de %s" % [b._lines, int(b.size.y), r, inner])
			check(absf(r.get_center().x - 396.0 * u) < 1.5, "%s h=%d: descentralizado" % [b._lines, int(b.size.y)])
		check(b._px >= 7, "%s h=%d: letra pequena demais (%d px)" % [b._lines, int(b.size.y), b._px])
	await RenderingServer.frame_post_draw
	var d := OS.get_environment("SHOT_DIR")
	if d != "": root.get_texture().get_image().save_png(d.path_join("emotes_todos.png"))
	print("itens: ", items.size())
	print("RESULT ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
