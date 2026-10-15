extends SceneTree
## R116 · PRÉVIA das molduras da Loja de Coroas (para aprovação): cada estilo num retrato quadrado e no redondo.
var fails := 0
func _initialize(): call_deferred("run")
func run():
	var size := Vector2i(1500, 640)
	root.size = size
	root.content_scale_size = size
	var bg := ColorRect.new()
	bg.color = Color("0b1530")
	bg.size = Vector2(size)
	root.add_child(bg)
	var Frame = load("res://monetization/club_frame.gd")
	var avatar: Texture2D = load("res://ui_v022/assets/profile_avatar.png")
	var styles := ["club", "fundador", "prata", "rubi", "safira", "jade", "ametista", "obsidiana"]
	var names := ["Club (atual)", "Fundador (atual)", "Prata", "Rubi", "Safira", "Jade", "Ametista", "Obsidiana"]
	var font: Font = load("res://account/fonts/Cinzel-Bold.woff")
	for i in styles.size():
		var x := 40 + i * 180
		for round in [false, true]:
			var holder := Control.new()
			holder.position = Vector2(x, 110 if not round else 380)
			holder.size = Vector2(130, 130)
			root.add_child(holder)
			var tr := TextureRect.new()
			tr.texture = avatar
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = holder.size
			holder.add_child(tr)
			var f = Frame.new()
			f.style = styles[i]
			f.round_shape = round
			holder.add_child(f)
		var l := Label.new()
		l.text = names[i]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color("f4ce7f"))
		l.position = Vector2(x - 10, 560)
		l.size = Vector2(150, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(l)
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("molduras_previa.png"))
	quit()
