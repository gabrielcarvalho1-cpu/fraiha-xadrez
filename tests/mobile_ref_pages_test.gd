extends SceneTree
## R53 · Celular: MAIS, CONHEÇA O FRAIHA e HISTÓRICO no visual das referências (ui_v022/mobile_ref_page.gd).
## Toques de verdade (InputEventScreenTouch), VOLTAR, ações do MAIS, rolagem, giro do celular e estabilidade
## (nada é recriado por quadro; reabrir não acumula nós).
## Uso: xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/mobile_ref_pages_test.gd -- --mobile-test --size 390x844
var failures := 0
var stage
var hub
var mob

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames(n := 3):
	for i in n: await process_frame

func tap(c: Control):
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = p
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

func on_screen(c: Control) -> bool:
	return c.is_visible_in_tree() and root.get_visible_rect().grow(1).encloses(c.get_global_rect())

func hot(caption: String) -> Button:
	return mob.ref_page.find_child("Ref_" + caption.replace(" ", "_"), true, false)

## rola o painel até o botão aparecer e toca
func tap_hot(caption: String) -> bool:
	var b := hot(caption)
	if b == null: return false
	mob.ref_page.scroll.ensure_control_visible(b)
	await frames(3)
	if not on_screen(b): return false
	await tap(b)
	await frames(4)
	return true

func count_nodes(n: Node) -> int:
	var c := 1
	for k in n.get_children(): c += count_nodes(k)
	return c

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hub = stage.get_node("MainHub")
	mob = hub.mobile_ui
	var tag := "%dx%d" % [size.x, size.y]
	check(is_instance_valid(mob), "Home do celular ativa (%s)" % tag)

	# ---------------- MAIS
	mob.show_page("mais")
	await frames(6)
	var rp = mob.ref_page
	check(rp != null and rp.visible and rp.page_id == "mais", "MAIS abre o painel da referência")
	check(rp.panel.size.x <= minf(size.x, 460.0) + 0.5 and rp.panel.position.x >= -0.5, "painel cabe na largura (%.0f px)" % rp.panel.size.x)
	check(not mob.heading.is_visible_in_tree() and not mob.scroll.is_visible_in_tree() and not mob.back_button.is_visible_in_tree(), "página antiga do celular não aparece por trás")
	for t in ["VOLTAR", "CONFIGURAÇÕES", "CONHEÇA O FRAIHA", "SAIR"]:
		var b := hot(t)
		check(b != null and b.size.y >= 44.0 * minf(1.0, size.x / 390.0) * 0.9 and b.size.x > 200, "MAIS: botão %s com área de toque (%s)" % [t, str(b.size) if b != null else "-"])
	var sair := hot("SAIR")
	var src = mob._source_button("SAIR")
	check(src != null and sair != null, "SAIR ligado ao SAIR da Home")
	check(await tap_hot("CONFIGURAÇÕES") and mob.current_page == "settings" and not rp.visible, "MAIS › CONFIGURAÇÕES abre as Configurações")
	check(mob.find_child("MusicVolumeMobile", true, false) != null, "Configurações montadas (volume)")
	hub.back()
	await frames(4)
	mob.show_page("mais")
	await frames(4)
	check(await tap_hot("CONHEÇA O FRAIHA") and rp.visible and rp.page_id == "about", "MAIS › CONHEÇA O FRAIHA abre o painel do Conheça")
	check(await tap_hot("VOLTAR") and hub.page == "main" and not rp.visible, "VOLTAR do Conheça volta à Home")
	mob.show_page("mais")
	await frames(4)
	check(await tap_hot("VOLTAR") and mob.current_page == "main" and not rp.visible, "VOLTAR do MAIS volta à Home")

	# ---------------- CONHEÇA: 6 tópicos, rolagem até o fim
	hub.show_page("about")
	await frames(6)
	var last: Control = rp.find_child("AboutTextMobile5", true, false)
	check(last != null, "último tópico montado")
	var bar: VScrollBar = rp.scroll.get_v_scroll_bar()
	check(bar.max_value > bar.page, "conteúdo maior que a tela: rola")
	rp.scroll.scroll_vertical = int(bar.max_value)
	await frames(3)
	check(last != null and rp.panel.get_global_rect().end.y <= root.get_visible_rect().size.y + 2.0, "fim do painel (moldura de baixo) alcançável")
	var n0 := count_nodes(rp)
	await frames(30)
	check(count_nodes(rp) == n0, "sem nós novos por quadro (%d)" % n0)

	# ---------------- giro do celular: painel refeito na largura nova, mesma página, sem aviso de girar
	var turned := Vector2i(size.y, size.x)
	root.size = turned
	root.content_scale_size = turned
	await frames(8)
	check(rp.visible and rp.page_id == "about" and rp.panel.size.x <= minf(turned.x, 460.0) + 0.5, "girou: Conheça continua, painel na largura nova (%.0f)" % rp.panel.size.x)
	check(absf(rp.panel.get_global_rect().get_center().x - turned.x / 2.0) < 2.0, "girou: painel centralizado")
	var banner := false
	for l in root.find_children("*", "Label", true, false):
		if l.is_visible_in_tree() and String(l.text).to_lower().contains("gire"): banner = true
	check(not banner, "nenhum aviso de \"gire o celular\"")
	root.size = size
	root.content_scale_size = size
	await frames(8)

	# ---------------- HISTÓRICO
	hub.show_page("history")
	await frames(6)
	check(rp.visible and rp.page_id == "history", "HISTÓRICO abre o painel da referência")
	var list: Control = rp.find_child("HistoryListMobile", true, false)
	check(list != null, "lista do histórico dentro do pergaminho")
	if list != null:
		var empty = list.get_node_or_null("HistoryEmpty")
		var rows := list.get_children().filter(func(c): return c is PanelContainer)
		check(empty != null or rows.size() > 0, "histórico: estado vazio ou partidas (%d)" % rows.size())
		var inside := true
		var pr: Rect2 = rp.panel.get_global_rect()
		for r in rows:
			var g: Rect2 = r.get_global_rect()
			if g.position.x < pr.position.x + 40.0 * rp.s or g.end.x > pr.end.x - 40.0 * rp.s: inside = false
		check(inside, "linhas do histórico dentro do pergaminho (largura)")
		if rows.size() > 0:
			var az: Button = rows[0].find_child("HistoryAnalyze", true, false)
			check(az != null and az.size.y >= 30.0, "ANALISAR com área de toque")
	var n1 := count_nodes(mob)
	for k in 3:
		hub.show_page("history")
		await frames(4)
	await frames(4)
	check(count_nodes(mob) <= n1 + 2, "reabrir não acumula nós (%d → %d)" % [n1, count_nodes(mob)])
	rp.scroll.scroll_vertical = 0
	await frames(3)
	check(await tap_hot("VOLTAR") and hub.page == "main" and not rp.visible, "VOLTAR do Histórico volta à Home")

	# ---------------- LIGAS E RANKING
	hub.show_page("ranking")
	await frames(6)
	check(rp.visible and rp.page_id == "ranking", "LIGAS abre o painel da referência")
	var ids: Array = hub.LeagueCatalog.IDS
	var rows_ok := true
	for id in ids:
		var row: TextureRect = rp.find_child("LeagueRow_" + id, true, false)
		var crest: TextureRect = rp.find_child("LeagueCrest_" + id, true, false)
		if row == null or crest == null or crest.texture == null: rows_ok = false
		elif not hub.league_unlocked(id) and not String(row.texture.resource_path).ends_with("ligas_mid_off.png"): rows_ok = false
		elif hub.league_unlocked(id) and String(row.texture.resource_path).ends_with("ligas_mid_off.png"): rows_ok = false
	check(rows_ok, "11 ligas com brasão oficial; bloqueadas no estilo bloqueado, liberadas no disponível")
	var head: Label = rp.find_child("RankingHeaderMobile", true, false)
	check(head != null and head.text.begins_with(String(hub.player_name)) and head.text.ends_with("/ 100 PL"), "faixa do jogador com nome, liga e PL: " + (head.text if head != null else "-"))
	var locked_id := ""
	for id in ids:
		if not hub.league_unlocked(id):
			locked_id = id
			break
	if not locked_id.is_empty():
		var theme_before: String = String(stage.theme_manager.active_theme) if stage.get("theme_manager") != null and "active_theme" in stage.theme_manager else ""
		var cap := "LIGA " + String(hub.LeagueCatalog.NAMES[hub.LeagueCatalog.index_of(locked_id)]).to_upper()
		check(await tap_hot(cap) and hub.selected_league == locked_id, "toque em %s (bloqueada) mostra a liga sem liberar" % cap)
		var row_l: TextureRect = rp.find_child("LeagueRow_" + locked_id, true, false)
		check(row_l != null and String(row_l.texture.resource_path).ends_with("ligas_mid_off.png"), "liga bloqueada continua no estilo bloqueado")
		if not theme_before.is_empty(): check(String(stage.theme_manager.active_theme) == theme_before, "liga bloqueada não troca o cenário")
	check(await tap_hot("LIGA MADEIRA") and hub.selected_league == "madeira", "toque na MADEIRA escolhe a liga")
	var row_m: TextureRect = rp.find_child("LeagueRow_madeira", true, false)
	check(row_m != null and String(row_m.texture.resource_path).ends_with("ligas_mid_sel.png"), "liga escolhida em destaque (moldura dourada)")
	var cp_before: String = hub.current_piece_set
	check(await tap_hot("PEÇAS CLÁSSICAS") and hub.current_piece_set != cp_before, "PEÇAS CLÁSSICAS alterna o conjunto (%s → %s)" % [cp_before, hub.current_piece_set])
	var sub: Label = rp.find_child("ClassicPiecesSubMobile", true, false)
	check(sub != null and sub.text == ("Em uso · toque para desligar" if hub.current_piece_set == "classic" else "Usar o conjunto original"), "estado das peças clássicas acompanha")
	await tap_hot("PEÇAS CLÁSSICAS")
	check(hub.current_piece_set == cp_before, "segundo toque volta ao conjunto anterior")
	rp.scroll.scroll_vertical = 0
	await frames(3)
	check(await tap_hot("VOLTAR") and hub.page == "main" and not rp.visible, "VOLTAR das Ligas volta à Home")

	# ---------------- JOGAR CONTRA O COMPUTADOR
	hub.show_page("bot")
	await frames(6)
	check(rp.visible and rp.page_id == "bot", "BOTS abre o painel da referência")
	var Ladder = load("res://bot/bot_ladder.gd")
	var all_ok := true
	var first_open := ""
	for b in Ladder.bots():
		var bid := String(b.id)
		var st: String = hub.bot_progress.status(bid)
		var card = rp.find_child("BotCard_" + bid, true, false)
		var stl: Label = rp.find_child("BotStatus_" + bid, true, false)
		var btl: Label = rp.find_child("BotButton_" + bid, true, false)
		var want: String = {"defeated": "DERROTADO", "available": "DISPONÍVEL", "locked": "BLOQUEADO"}[st]
		var want_b: String = {"defeated": "JOGAR DE NOVO", "available": "DESAFIAR", "locked": "BLOQUEADO"}[st]
		if card == null or stl == null or stl.text != want or btl == null or btl.text != want_b: all_ok = false
		if (hot("DESAFIAR " + bid) != null) == (st == "locked"): all_ok = false   # bloqueado não tem toque
		if first_open.is_empty() and st != "locked": first_open = bid
	check(all_ok, "11 bots com estado, botão e toque conforme o progresso real")
	if not first_open.is_empty():
		check(await tap_hot("DESAFIAR " + first_open) and hub.page == "bot_side" and not rp.visible, "DESAFIAR abre ESCOLHA SEU LADO (%s)" % first_open)
		hub.back()
		await frames(6)
		check(hub.page == "bot" and rp.visible and rp.page_id == "bot", "voltar do lado retorna à escada")
	var bar_b: VScrollBar = rp.scroll.get_v_scroll_bar()
	rp.scroll.scroll_vertical = int(bar_b.max_value)
	await frames(3)
	check(await tap_hot("VOLTAR_FIM") and hub.page == "main" and not rp.visible, "VOLTAR do fim da escada volta à Home")

	# ---------------- PERFIL
	hub.show_page("profile")
	await frames(6)
	check(rp.visible and rp.page_id == "profile", "PERFIL abre o painel da referência")
	var gal = rp.find_child("AvatarGalleryMobile", true, false)
	var cnt: Label = rp.find_child("GalleryCountRefMobile", true, false)
	check(gal != null and gal.ref_cards and gal.columns == 3, "galeria de avatares em 3 colunas com os cartões da referência")
	check(cnt != null and gal != null and cnt.text == "%d de %d" % [gal.count_unlocked(), gal.cards.size()], "COLEÇÃO DE AVATARES com o número real (%s)" % (cnt.text if cnt else "-"))
	if gal != null:
		var pr2: Rect2 = rp.panel.get_global_rect()
		var inside2 := true
		for id in gal.cards:
			var g: Rect2 = gal.cards[id].get_global_rect()
			if g.position.x < pr2.position.x or g.end.x > pr2.end.x: inside2 = false
		check(inside2, "cartões dentro do painel (largura)")
		var before_av: String = hub.avatar_id
		var pick := ""
		var locked_av := ""
		for id in gal.cards:
			var st: String = gal.state_of(id)
			if st == "unlocked" and pick.is_empty(): pick = id
			if st == "locked" and locked_av.is_empty(): locked_av = id
		var apply: Button = rp.find_child("ApplyAvatarMobile", true, false)
		if not locked_av.is_empty():
			rp.scroll.ensure_control_visible(gal.cards[locked_av])
			await frames(3)
			await tap(gal.cards[locked_av])
			await frames(2)
			check(apply != null and apply.disabled, "avatar bloqueado: APLICAR desabilitado")
		if not pick.is_empty():
			rp.scroll.ensure_control_visible(gal.cards[pick])
			await frames(3)
			await tap(gal.cards[pick])
			await frames(2)
			check(apply != null and not apply.disabled, "avatar conquistado: APLICAR liberado")
			rp.scroll.ensure_control_visible(apply)
			await frames(3)
			await tap(apply)
			await frames(3)
			check(hub.avatar_id == pick and gal.state_of(pick) == "selected", "APLICAR AVATAR troca o avatar de verdade (%s)" % pick)
			var card_sel = gal.cards[pick]
			check(card_sel.ref_sub != null and card_sel.ref_sub.text == "EM USO", "cartão mostra EM USO")
			hub.apply_avatar(before_av)
			await frames(2)
	rp.scroll.scroll_vertical = 0
	await frames(3)
	check(await tap_hot("VOLTAR") and hub.page == "main" and not rp.visible, "VOLTAR do Perfil volta à Home")
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
