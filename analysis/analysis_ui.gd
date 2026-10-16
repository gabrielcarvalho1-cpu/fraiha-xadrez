extends CanvasLayer
## Tela de ANÁLISE DE PARTIDA do FRAIHA (pós-partida).
## Páginas: "quota" (sem análises) → "progress" (ANALISANDO...) → "report" (resumo, gráfico,
## revisão lance a lance, VER MELHOR LANCE, TENTAR NOVAMENTE, TREINE MEUS ERROS).
## Identidade própria: pergaminho, verde, dourado; animações discretas por classe de lance.
signal closed
signal train_requested(report: Dictionary)

const Art := preload("res://monetization/premium_art.gd")
const Config := preload("res://analysis/analysis_config.gd")
const Notation := preload("res://analysis/notation.gd")
const Mobile := preload("res://ui_v022/mobile_layout.gd")
const ReviewBoard := preload("res://analysis/review_board.gd")
const EvalGraph := preload("res://analysis/eval_graph.gd")
const Export := preload("res://analysis/export.gd")

var engine
var analyzer
var access
var hub                       # main_hub (Premium, entitlements)
var eval_bar                  # R130 · barra de avaliação ao lado do tabuleiro
var record
var report := {}
var page := ""
var root: Control
var sparkles: Control
var column: VBoxContainer
var scroll: ScrollContainer
var header_label: Label
var back_button: Button
var board: ReviewBoard
var graph: EvalGraph
var move_list: VBoxContainer
var detail: VBoxContainer
var progress_bar: ProgressBar
var progress_label: Label
var progress_board: ReviewBoard
var progress_burst: Control
var cur_ply := -1
var showing_best := false
var trying := false
var try_board: ReviewBoard
var try_panel: VBoxContainer
var try_status: Label
var k := 1.0
var narrow := false
var move_buttons := {}

func _init(p_engine, p_access, p_hub):
    layer = 65
    preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC em tudo (fecha só a janela de cima)
    name = "AnalysisUI"
    engine = p_engine
    access = p_access
    hub = p_hub
    analyzer = load("res://analysis/analyzer.gd").new(engine)

func _ready():
    add_child(analyzer)
    analyzer.progress.connect(_on_progress)
    _build()
    get_viewport().size_changed.connect(_relayout)
    visible = false

# ---------------------------------------------------------------- abrir/fechar
## Abre pedindo a autorização de cota ao servidor; começa a análise se concedida.
func open_for(p_record):
    record = p_record
    report = {}
    visible = true
    root.visible = true
    _show_page("asking")
    access.granted.connect(_on_granted, CONNECT_ONE_SHOT)
    access.denied.connect(_on_denied, CONNECT_ONE_SHOT)
    access.request()

## Abre um relatório já pronto (histórico).
func open_report(p_record, p_report: Dictionary):
    record = p_record
    report = p_report
    visible = true
    root.visible = true
    _show_page("report")

func close():
    if analyzer.running: analyzer.cancel()
    if engine != null: engine.cancel()
    visible = false
    root.visible = false
    closed.emit()

func _on_granted(_unlimited: bool):
    if access.denied.is_connected(_on_denied): access.denied.disconnect(_on_denied)
    _show_page("progress")
    _run()

func _on_denied(code: String, message: String):
    if access.granted.is_connected(_on_granted): access.granted.disconnect(_on_granted)
    _show_page("quota")

func _run():
    if not engine.engine_ready: await engine.start()
    var prof: Dictionary = preload("res://analysis/analysis_config.gd").engine_profile(engine.transport)
    analyzer.depth = int(prof.depth)
    analyzer.max_ms_per_pos = int(prof.max_ms)
    var rep: Dictionary = await analyzer.analyze(record)
    if rep.is_empty() or not visible: return
    report = rep
    _show_page("report")

func esc_open() -> bool:
    return visible

func esc_close():
    if trying: _end_try()
    else: close()

func _input(event):
    if not visible: return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            if trying: _end_try()
            else: close()
            get_viewport().set_input_as_handled()
        elif page == "report" and not trying:
            if event.keycode == KEY_LEFT: _goto(cur_ply - 1)
            elif event.keycode == KEY_RIGHT: _goto(cur_ply + 1)
            elif event.keycode == KEY_HOME: _goto(-1)
            elif event.keycode == KEY_END: _goto(report.moves.size() - 1)

# ---------------------------------------------------------------- estrutura
func _build():
    root = Control.new()
    root.name = "AnalysisRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    var bg := Control.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.draw.connect(func():
        bg.draw_rect(Rect2(Vector2.ZERO, bg.size), Color(0.014, 0.029, 0.057, 1.0))
        for i in 8: bg.draw_circle(Vector2(bg.size.x * 0.5, -bg.size.y * 0.2), bg.size.x * (0.2 + i * 0.08), Color(1.0, 0.78, 0.35, 0.03 * (1.0 - i / 8.0))))
    root.add_child(bg)
    sparkles = Art.Sparkles.new(24)
    root.add_child(sparkles)
    var outer := VBoxContainer.new()
    outer.name = "AnalysisOuter"
    outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    outer.add_theme_constant_override("separation", 8)
    root.add_child(outer)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    outer.add_child(header)
    back_button = Art.Cta.new("FECHAR", "dark", 50, 17)
    back_button.name = "AnalysisBack"
    back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # nunca estica na altura
    back_button.pressed.connect(func():
        if trying: _end_try()
        else: close())
    header.add_child(back_button)
    header_label = Art.label(header, "ANÁLISE DA PARTIDA", 24, Art.GOLD, Art.FONT_BOLD)
    header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    header_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    var quota_tag := Art.Stamp.new("", "info", 13)
    quota_tag.name = "QuotaTag"
    header.add_child(quota_tag)
    # Celular em pé: o selo da cota vai para uma linha própria (senão o título fica sem largura).
    var tag_row := HBoxContainer.new()
    tag_row.name = "QuotaRow"
    tag_row.alignment = BoxContainer.ALIGNMENT_END
    tag_row.visible = false
    outer.add_child(tag_row)
    scroll = ScrollContainer.new()
    scroll.name = "AnalysisScroll"
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    outer.add_child(scroll)
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    var center := CenterContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(center)
    column = VBoxContainer.new()
    column.name = "AnalysisColumn"
    column.add_theme_constant_override("separation", 16)
    center.add_child(column)
    _relayout()

func _relayout():
    if root == null: return
    var vs := root.get_viewport_rect().size
    narrow = vs.x < 760.0
    k = 1.0 if vs.x >= 1100.0 else (0.86 if vs.x >= 760.0 else 0.76)
    var gutter := 14.0 if narrow else 36.0
    var outer: Control = root.get_node("AnalysisOuter")
    outer.offset_left = gutter
    outer.offset_right = -gutter
    outer.offset_top = 12.0
    outer.offset_bottom = -8.0
    column.custom_minimum_size.x = minf(vs.x - gutter * 2.0 - 16.0, 1240.0)
    header_label.add_theme_font_size_override("font_size", fs(24))
    back_button.custom_minimum_size = Vector2(120 if narrow else 160, 46)
    var tag = root.find_child("QuotaTag", true, false)
    var tag_row = root.find_child("QuotaRow", true, false)
    if tag != null and tag_row != null:
        var want: Node = tag_row if narrow else back_button.get_parent()
        if tag.get_parent() != want:
            tag.get_parent().remove_child(tag)
            want.add_child(tag)
        tag_row.visible = narrow
    if visible and page != "": _show_page(page)

func fs(n: int) -> int:
    return maxi(11, int(round(n * k)))

func _clear():
    for c in column.get_children():
        column.remove_child(c)
        c.queue_free()
    move_buttons.clear()

func _quota_tag():
    var tag = root.find_child("QuotaTag", true, false)
    if tag == null: return
    tag.set_text("CLUB · ILIMITADO" if access.club_unlimited() else "ANÁLISES GRATUITAS  " + access.counter_text())
    tag.tone = "ok" if access.club_unlimited() else "info"
    tag.queue_redraw()

func _show_page(id: String):
    page = id
    _clear()
    _quota_tag()
    match id:
        "asking": _page_asking()
        "quota": _page_quota()
        "progress": _page_progress()
        "report": _page_report()
    scroll.scroll_vertical = 0

# ---------------------------------------------------------------- páginas simples
func _page_asking():
    var f := Art.Frame.new("dark", 26)
    column.add_child(f)
    var v := VBoxContainer.new()
    f.add_child(v)
    Art.label(v, "Verificando suas análises…", fs(20), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)

func _page_quota():
    var f := Art.Frame.new("founder", 28)
    f.name = "QuotaPanel"
    column.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    f.add_child(v)
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(row)
    row.add_child(Art.Glyph.new("hourglass", 64, Art.GOLD, true))
    Art.label(v, "VOCÊ USOU SUAS\n%d ANÁLISES GRATUITAS DE HOJE" % access.limit, fs(28), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, "ANÁLISES GRATUITAS  %s" % access.counter_text(), fs(18), Art.CREAM, Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, "O limite %s. Com o Club FRAIHA, as análises são ilimitadas." % access.reset_text(), fs(16), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    var cta := Art.Cta.new("ATIVAR CLUB FRAIHA", "green", 62, 21)
    cta.name = "QuotaActivateClub"
    cta.icon_kind = "crown"
    cta.shimmer = true
    cta.pressed.connect(func():
        close()
        if hub != null: hub.open_club())
    v.add_child(cta)
    var later := Art.Cta.new("VOLTAR", "dark", 50, 17)
    later.pressed.connect(close)
    v.add_child(later)

# ---------------------------------------------------------------- progresso
## ANALISANDO: ocupa a tela toda (painel na altura disponível), tabuleiro grande acompanhando
## os lances, porcentagem, barra e os últimos lances anotados (sem rótulos de classificação).
func _page_progress():
    var vs := root.get_viewport_rect().size
    var f := Art.Frame.new("club", 24)
    f.name = "ProgressPanel"
    f.custom_minimum_size.y = maxf(320.0, vs.y - 12.0 - 8.0 - 46.0 - 8.0 - 8.0)
    f.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    v.size_flags_vertical = Control.SIZE_EXPAND_FILL
    f.add_child(v)
    var t := Art.label(v, "ANALISANDO SUA PARTIDA", fs(32), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    t.name = "ProgressTitle"
    Art.label(v, "O motor revisa cada lance; ao final você vê a avaliação e pode guardar os lances.", fs(14), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    var layout: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    layout.add_theme_constant_override("separation", 28)
    layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layout.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(layout)
    progress_board = ReviewBoard.new()
    var side_px := minf(column.custom_minimum_size.x - 8.0, 380.0) if narrow else clampf(f.custom_minimum_size.y - 190.0, 320.0, 640.0)
    progress_board.custom_minimum_size = Vector2(side_px, side_px)
    progress_board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    progress_board.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    progress_board.flipped = String(record.human_color) == "b"
    progress_board.show_fen(Notation.fen(record.position_after(0)), false)
    layout.add_child(progress_board)
    var side := VBoxContainer.new()
    side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    side.add_theme_constant_override("separation", 12)
    layout.add_child(side)
    var pct := Art.label(side, "0%", fs(64), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    pct.name = "ProgressPercent"
    progress_label = Art.label(side, "LANCE 0 DE %d" % record.moves.size(), fs(22), Art.CREAM, Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    progress_label.name = "ProgressLabel"
    progress_bar = ProgressBar.new()
    progress_bar.name = "ProgressBar"
    progress_bar.max_value = maxi(1, record.moves.size())
    progress_bar.value = 0
    progress_bar.show_percentage = false
    progress_bar.custom_minimum_size.y = 22
    var bgs := StyleBoxFlat.new()
    bgs.bg_color = Color(0.042, 0.066, 0.113)
    bgs.border_color = Color("c99a45")
    bgs.set_border_width_all(1)
    bgs.set_corner_radius_all(8)
    var fgs := StyleBoxFlat.new()
    fgs.bg_color = Color("e9c46a")
    fgs.set_corner_radius_all(8)
    progress_bar.add_theme_stylebox_override("background", bgs)
    progress_bar.add_theme_stylebox_override("fill", fgs)
    side.add_child(progress_bar)
    var ff := Art.Frame.new("dark", 12)
    ff.custom_minimum_size.y = 170 if narrow else 230
    side.add_child(ff)
    var fv := VBoxContainer.new()
    fv.add_theme_constant_override("separation", 4)
    ff.add_child(fv)
    Art.label(fv, "ÚLTIMOS LANCES ANOTADOS", fs(12), Art.GOLD, Art.FONT_SEMI)
    var feed := VBoxContainer.new()
    feed.name = "ProgressFeed"
    feed.add_theme_constant_override("separation", 3)
    fv.add_child(feed)
    var eng := Art.label(side, "", fs(13), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    eng.name = "ProgressEngine"
    _refresh_engine_line()
    if not engine.ready_changed.is_connected(_refresh_engine_line): engine.ready_changed.connect(_refresh_engine_line)
    var cancel := Art.Cta.new("CANCELAR", "ember", 52, 18)
    cancel.name = "AnalysisCancel"
    cancel.pressed.connect(close)
    side.add_child(cancel)

func _refresh_engine_line(_v = null):
    var eng = root.find_child("ProgressEngine", true, false)
    if eng == null: return
    var nm := String(engine.engine_name)
    if nm.is_empty(): eng.text = "Iniciando o motor de análise…"
    else: eng.text = "%s%s · profundidade %d" % ["" if nm.begins_with("Motor") else "Motor: ", nm, analyzer.depth]

func _on_progress(done: int, total: int, m: Dictionary):
    if page != "progress": return
    if is_instance_valid(progress_label): progress_label.text = "LANCE %d DE %d" % [done, total]
    var pct = root.find_child("ProgressPercent", true, false)
    if pct != null: pct.text = "%d%%" % int(round(100.0 * done / maxf(1.0, total)))
    if is_instance_valid(progress_bar):
        var tw := create_tween()
        tw.tween_property(progress_bar, "value", float(done), 0.25)
    if is_instance_valid(progress_board):
        var mv := Notation.uci_to_move(String(m.uci))
        progress_board.show_fen(String(m.fen_after), true, mv.from, mv.to)
        progress_board.set_mark("", "", Color.WHITE)
    var feed = root.find_child("ProgressFeed", true, false)
    if feed != null:
        var who := ("%d. " % (int(m.ply) / 2 + 1)) if m.color == "w" else ("%d… " % (int(m.ply) / 2 + 1))
        var l := Art.label(feed, who + String(m.san), fs(16), Art.CREAM)
        l.modulate.a = 0.0
        var tw2 := create_tween()
        tw2.tween_property(l, "modulate:a", 1.0, 0.3)
        while feed.get_child_count() > (6 if narrow else 8):
            var first := feed.get_child(0)
            feed.remove_child(first)
            first.queue_free()

## Efeitos por classe: brilho (bom), tremor (erro), explosão de faíscas (erro grave/lendário).
func _class_effect(cls: String):
    var target: Control = progress_board if page == "progress" else board
    if not is_instance_valid(target): return
    match cls:
        "best", "excellent":
            var tw := create_tween()
            tw.tween_property(target, "modulate", Color(1.15, 1.12, 1.0), 0.12)
            tw.tween_property(target, "modulate", Color.WHITE, 0.35)
        "brilliant", "legendary":
            var burst := Art.Sparkles.new(60, Config.COLORS[cls])
            target.add_child(burst)
            var tw := create_tween()
            tw.tween_interval(1.6)
            tw.tween_callback(func(): if is_instance_valid(burst): burst.queue_free())
        "mistake", "missed":
            var tw := create_tween()
            var p := target.position
            tw.tween_property(target, "position:x", p.x + 4.0, 0.05)
            tw.tween_property(target, "position:x", p.x - 4.0, 0.05)
            tw.tween_property(target, "position:x", p.x, 0.05)
        "blunder":
            var tw := create_tween()
            var p := target.position
            tw.tween_property(target, "modulate", Color(1.3, 0.7, 0.65), 0.08)
            for i in 3:
                tw.tween_property(target, "position:x", p.x + 6.0, 0.04)
                tw.tween_property(target, "position:x", p.x - 6.0, 0.04)
            tw.tween_property(target, "position:x", p.x, 0.04)
            tw.tween_property(target, "modulate", Color.WHITE, 0.4)

# ---------------------------------------------------------------- relatório
func _page_report():
    trying = false
    showing_best = false
    var human: String = String(report.human_color)
    var me: Dictionary = report.players.get(human if human != "" else "w", {})
    var opp: Dictionary = report.players.get("b" if human == "w" else "w", {})
    # R130 · RESUMO = DUELO: os dois jogadores (retrato + nome), o resultado no meio e a precisão em anéis dourados
    var AA := preload("res://analysis/analysis_art.gd")
    var sum := MarginContainer.new()
    sum.name = "SummaryPanel"
    sum.custom_minimum_size.y = 250 if narrow else 330
    column.add_child(sum)
    sum.add_child(AA.Backdrop.new(load("res://analysis/art/duelo_fundo.png")))
    var pad := MarginContainer.new()
    for side_m in ["left", "right"]: pad.add_theme_constant_override("margin_" + side_m, 14 if narrow else 34)
    for side_m in ["top", "bottom"]: pad.add_theme_constant_override("margin_" + side_m, 16 if narrow else 22)
    sum.add_child(pad)
    var sv := VBoxContainer.new()
    sv.add_theme_constant_override("separation", 14)
    pad.add_child(sv)
    var res: String = {"win": "VITÓRIA", "loss": "DERROTA", "draw": "EMPATE"}.get(String(report.result), "")
    var res_col: Color = {"win": Color("8ff0a4"), "loss": Color("ff7a66"), "draw": Color("dfe6f0")}.get(String(report.result), Art.GOLD)
    var duel := HBoxContainer.new()
    duel.name = "DuelRow"
    duel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    duel.add_theme_constant_override("separation", 8)
    sv.add_child(duel)
    var names := Export.names(record)
    var my_name: String = names[1] if human == "b" else names[0]
    var opp_name: String = names[0] if human == "b" else names[1]
    var ring_side := 112.0 if narrow else 168.0
    for side in ["me", "center", "opp"]:
        if side == "center":
            var cv := VBoxContainer.new()
            cv.alignment = BoxContainer.ALIGNMENT_END
            cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            cv.add_theme_constant_override("separation", 2)
            duel.add_child(cv)
            var plate := MarginContainer.new()
            plate.add_theme_constant_override("margin_top", 6)
            plate.add_theme_constant_override("margin_bottom", 8)
            cv.add_child(plate)
            plate.add_child(AA.ResultPlate.new())
            var pv := VBoxContainer.new()
            pv.add_theme_constant_override("separation", 0)
            plate.add_child(pv)
            if res != "":
                var rl := AA.big(pv, res, fs(44 if not narrow else 26), res_col, Color(0, 0, 0, 0.9))
                rl.name = "DuelResult"
            var mode_names := {"bot": "Contra o computador", "casual": "Online casual", "ranked": "Ranqueada", "local": "Local", "friend": "Amigo"}
            AA.caps(pv, "%s  ·  %s" % [String(mode_names.get(String(record.mode), "Partida")).to_upper(), Export.date_text(record)], fs(14), Color("f3dfae"), HORIZONTAL_ALIGNMENT_CENTER)
            continue
        var data: Dictionary = me if side == "me" else opp
        var col := VBoxContainer.new()
        col.alignment = BoxContainer.ALIGNMENT_CENTER
        col.add_theme_constant_override("separation", 10)
        col.custom_minimum_size.x = 150 if narrow else 300
        duel.add_child(col)
        var head := HBoxContainer.new()
        head.alignment = BoxContainer.ALIGNMENT_CENTER
        head.add_theme_constant_override("separation", 12)
        col.add_child(head)
        head.add_child(AA.Portrait.new(_portrait_tex(side == "me"), 44.0 if narrow else 64.0, 1.22 if side == "me" else 1.0))
        var nv := VBoxContainer.new()
        nv.alignment = BoxContainer.ALIGNMENT_CENTER
        nv.add_theme_constant_override("separation", -2)
        head.add_child(nv)
        AA.caps(nv, "VOCÊ" if side == "me" else "ADVERSÁRIO", fs(14), Color("f5c451") if side == "me" else Color("cfd9e8"))
        var nl := AA.big(nv, my_name if side == "me" else opp_name, fs(26 if not narrow else 18), Color("fff6dc"), Color(0, 0, 0, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
        if narrow:
            nl.clip_text = true
            nl.custom_minimum_size.x = 80
        var rc := CenterContainer.new()
        col.add_child(rc)
        var ring := AA.Ring.new(float(data.get("accuracy", 0.0)), ring_side if narrow else ring_side * k, Color("f5c451") if side == "me" else Color("dfe6f0"))
        ring.label.name = "AccuracyMe" if side == "me" else "AccuracyOpp"
        rc.add_child(ring)
    # momentos: fora do painel da arte, cartões limpos (fundo escuro, filete fino, ícone colorido)
    var after_sum := VBoxContainer.new()
    after_sum.add_theme_constant_override("separation", 10)
    column.add_child(after_sum)
    sv = after_sum
    if bool(report.get("partial", false)):
        var note := "Análise parcial: a partida foi registrada a partir de uma reconexão (lances anteriores não entram)."
        if bool(report.get("start_fen_approx", false)): note += " Posição reconstruída sem histórico: roque e en passant foram considerados indisponíveis."
        var nl2 := Art.label(sv, note, fs(14), Color("f2b07a"))
        nl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # momentos: cartões clicáveis (estrela dourada / alvo em brasa)
    var moments: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    moments.add_theme_constant_override("separation", 14)
    sv.add_child(moments)
    for pair in [["MELHOR MOMENTO", int(me.get("best_moment", -1)), "star", Color("9de5a0")], ["PONTO CRÍTICO", int(me.get("critical", -1)), "target", Color("f2924f")]]:
        var ply: int = int(pair[1])
        if ply < 0: continue
        var b := Button.new()
        b.name = "Moment_" + String(pair[2])
        b.focus_mode = Control.FOCUS_NONE
        b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var bs := StyleBoxFlat.new()
        bs.bg_color = Color(0.045, 0.04, 0.035, 0.94)
        bs.border_color = Color("d9b25f", 0.55)
        bs.set_border_width_all(1)
        bs.set_corner_radius_all(6)
        b.add_theme_stylebox_override("normal", bs)
        var bh := bs.duplicate()
        bh.bg_color = Color(0.09, 0.12, 0.2, 0.95)
        b.add_theme_stylebox_override("hover", bh)
        b.add_theme_stylebox_override("pressed", bh)
        b.pressed.connect(func(): _goto(ply))
        moments.add_child(b)
        var hb := HBoxContainer.new()
        hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hb.add_theme_constant_override("separation", 12)
        hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        hb.offset_left = 16
        b.add_child(hb)
        hb.add_child(Art.Glyph.new(pair[2], 30, pair[3], false))
        var cl := VBoxContainer.new()
        cl.alignment = BoxContainer.ALIGNMENT_CENTER
        cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        cl.add_theme_constant_override("separation", 0)
        hb.add_child(cl)
        var l1 := AA.caps(cl, pair[0], fs(14), pair[3])
        l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var mv: Dictionary = report.moves[ply]
        var l2 := Art.label(cl, "Lance %d · %s" % [ply / 2 + 1, mv.san], fs(22), Art.CREAM, Art.FONT_BOLD)
        l2.autowrap_mode = TextServer.AUTOWRAP_OFF
        l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
        b.custom_minimum_size = Vector2(maxf(l1.get_minimum_size().x, l2.get_minimum_size().x) + 90.0, 70)
    # Gráfico
    var gf := preload("res://analysis/analysis_art.gd").panel(16)
    gf.name = "GraphPanel"
    column.add_child(gf)
    var gv := VBoxContainer.new()
    gv.add_theme_constant_override("separation", 6)
    gf.add_child(gv)
    preload("res://analysis/analysis_art.gd").caps(gv, "AVALIAÇÃO AO LONGO DA PARTIDA", fs(16), Art.GOLD)
    graph = EvalGraph.new()
    graph.name = "EvalGraph"
    graph.custom_minimum_size = Vector2(0, 150 if narrow else 190)
    graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    graph.set_moves(report.moves, true)
    graph.ply_selected.connect(_goto)
    gv.add_child(graph)
    # Revisão: tabuleiro + detalhe + lista
    var rev: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    rev.name = "ReviewRow"
    rev.add_theme_constant_override("separation", 18)
    column.add_child(rev)
    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 8)
    rev.add_child(left)
    board = ReviewBoard.new()
    board.name = "ReviewBoard"
    var side_px := minf(column.custom_minimum_size.x - 40.0, 420.0) if narrow else 520.0
    board.custom_minimum_size = Vector2(side_px, side_px)
    board.flipped = human == "b"
    # R130 · barra de AVALIAÇÃO ao lado do tabuleiro (Brancas claro / Pretas escuro), acompanha o lance
    var brow := HBoxContainer.new()
    brow.add_theme_constant_override("separation", 8)
    left.add_child(brow)
    eval_bar = preload("res://analysis/analysis_art.gd").EvalBar.new()
    eval_bar.name = "EvalBar"
    eval_bar.flipped = board.flipped
    eval_bar.custom_minimum_size = Vector2(22 if narrow else 28, side_px * 0.86)
    eval_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    brow.add_child(eval_bar)
    brow.add_child(board)
    var nav := HBoxContainer.new()
    nav.add_theme_constant_override("separation", 6)
    left.add_child(nav)
    for pair in [["|<", -999, "NavFirst"], ["<", -1, "NavPrev"], [">", 1, "NavNext"], [">|", 999, "NavLast"]]:
        var b := Art.Cta.new(pair[0], "dark", 46, 18)
        b.name = pair[2]
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var d: int = pair[1]
        b.pressed.connect(func():
            if d == -999: _goto(-1)
            elif d == 999: _goto(report.moves.size() - 1)
            else: _goto(cur_ply + d))
        nav.add_child(b)
    detail = VBoxContainer.new()
    detail.name = "MoveDetail"
    detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.add_theme_constant_override("separation", 10)
    rev.add_child(detail)
    # Lista de lances: anotação padrão (igual para todos), sem rótulos de classificação.
    # Botões para guardar a partida: copiar o texto, salvar .txt ou salvar um print.
    var lf := preload("res://analysis/analysis_art.gd").panel(16)
    lf.name = "MoveListPanel"
    column.add_child(lf)
    var lv := VBoxContainer.new()
    lv.add_theme_constant_override("separation", 8)
    lf.add_child(lv)
    var lh := HBoxContainer.new()
    lh.add_theme_constant_override("separation", 10)
    lv.add_child(lh)
    var lt := preload("res://analysis/analysis_art.gd").caps(lh, "LANCES DA PARTIDA", fs(16), Art.GOLD)
    lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    Art.label(lv, "%s (brancas) × %s (pretas) · %s" % [Export.names(record)[0], Export.names(record)[1], Export.date_text(record)], fs(13), Art.MUTED)
    var grid := GridContainer.new()
    grid.name = "MoveGrid"
    grid.columns = 3 if narrow else 6
    grid.add_theme_constant_override("h_separation", 4)
    grid.add_theme_constant_override("v_separation", 3)
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lv.add_child(grid)
    move_list = lv
    var move_font := fs(15)
    for i in report.moves.size():
        var m: Dictionary = report.moves[i]
        if m.color == "w" or i == 0:
            var num := Art.label(grid, "%d." % (i / 2 + 1), move_font, Art.GOLD, Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_RIGHT)
            num.size_flags_horizontal = Control.SIZE_SHRINK_END
            num.custom_minimum_size.x = 34
            if m.color == "b": grid.add_child(_move_cell("…", move_font, false))
        var b := Button.new()
        b.name = "Move_%d" % i
        b.focus_mode = Control.FOCUS_NONE
        b.text = String(m.san) + ("  *" if m.marked else "")   # * = marcado para revisar
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.custom_minimum_size.x = 92 if narrow else 110
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.add_theme_font_size_override("font_size", move_font)
        b.add_theme_color_override("font_color", Art.CREAM)
        b.add_theme_color_override("font_hover_color", Art.GOLD)
        b.add_theme_color_override("font_pressed_color", Art.GOLD)
        var st := StyleBoxFlat.new()
        st.bg_color = Color(0.070, 0.094, 0.141, 0.8)
        st.set_corner_radius_all(4)
        st.content_margin_left = 8
        st.content_margin_right = 8
        b.add_theme_stylebox_override("normal", st)
        var hv := st.duplicate()
        hv.bg_color = Color(0.162, 0.207, 0.297, 0.95)
        b.add_theme_stylebox_override("hover", hv)
        b.add_theme_stylebox_override("pressed", hv)
        var idx: int = i
        b.pressed.connect(func(): _goto(idx))
        grid.add_child(b)
        move_buttons[i] = b
    var sans := []
    for m in report.moves: sans.append(String(m.san))
    var export_text := Export.text_of(record, sans)
    var tools: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    tools.add_theme_constant_override("separation", 8)
    lv.add_child(tools)
    var cp := Art.Cta.new("COPIAR LANCES", "gold", 48, 15)
    cp.name = "CopyMoves"
    cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tools.add_child(cp)
    var st_txt := Art.Cta.new("SALVAR TEXTO (.txt)", "dark", 48, 15)
    st_txt.name = "SaveMovesText"
    st_txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tools.add_child(st_txt)
    var sp := Art.Cta.new("SALVAR PRINT (.png)", "dark", 48, 15)
    sp.name = "SaveScreenshot"
    sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tools.add_child(sp)
    var exp_status := Art.label(lv, "Guarde os lances para analisar depois: copie o texto, salve um .txt ou um print da tela.", fs(13), Art.MUTED)
    exp_status.name = "ExportStatus"
    cp.pressed.connect(func(): exp_status.text = Export.copy(export_text))
    st_txt.pressed.connect(func(): exp_status.text = Export.save_text(export_text, Export.file_stem(record)))
    sp.pressed.connect(func(): _save_screenshot(exp_status))
    # Treine meus erros
    var trainable := _trainable(human)
    var tf := preload("res://analysis/analysis_art.gd").panel(22)
    tf.name = "TrainPanel"
    column.add_child(tf)
    var tv := VBoxContainer.new()
    tv.add_theme_constant_override("separation", 8)
    tf.add_child(tv)
    Art.label(tv, "TREINE MEUS ERROS", fs(24), Art.GOLD, Art.FONT_BOLD)
    Art.label(tv, ("%d posições desta partida viram exercícios: encontre uma continuação melhor." % trainable.size()) if not trainable.is_empty() else "Nenhum erro relevante nesta partida — ótimo trabalho.", fs(16), Art.CREAM)
    var tb := Art.Cta.new("TREINE MEUS ERROS", "green", 60, 20)
    tb.name = "TrainButton"
    tb.icon_kind = "sword"
    tb.disabled = trainable.is_empty()
    tb.pressed.connect(func(): train_requested.emit(report))
    tv.add_child(tb)
    var tail := Control.new()
    tail.custom_minimum_size.y = 30
    column.add_child(tail)
    # começa no ponto crítico (ou no primeiro lance)
    _goto(int(me.get("critical", -1)) if int(me.get("critical", -1)) >= 0 else -1, false)

## R130 · retrato do duelo: o seu avatar; o adversário = brasão da liga do bot (ou o avatar padrão).
func _portrait_tex(mine: bool) -> Texture2D:
    if mine:
        if hub != null and hub.has_method("avatar_texture"): return hub.avatar_texture(String(hub.get("avatar_id")))
        return null
    if String(record.mode) == "bot":
        var Ladder = load("res://bot/bot_ladder.gd")
        for id in Ladder.ids():
            var bot: Dictionary = Ladder.bot(id)
            if String(bot.get("name", "")).to_upper() == String(record.opponent_name).to_upper():
                return load("res://cosmetics/theme_catalog.gd").badge_texture(String(bot.get("league", id)))
    if hub != null and hub.has_method("avatar_texture"): return hub.avatar_texture("warrior")
    return null

func _move_cell(text: String, size: int, bold: bool) -> Label:
    var l := Art.label(null, text, size, Art.MUTED, Art.FONT_SEMI if bold else null)
    l.autowrap_mode = TextServer.AUTOWRAP_OFF
    return l

## SALVAR PRINT: captura a tela inteira da análise (gráfico, tabuleiro e lances) num PNG.
func _save_screenshot(status_label: Label):
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    status_label.text = Export.save_png(img, Export.file_stem(record))

func _plural(cls: String, n: int) -> String:
    var names := {"legendary": ["Lendário", "Lendários"], "brilliant": ["Extraordinário", "Extraordinários"], "best": ["Melhor Lance", "Melhores Lances"],
        "excellent": ["Excelente", "Excelentes"], "good": ["Bom", "Bons"], "book": ["Teórico", "Teóricos"], "inaccuracy": ["Imprecisão", "Imprecisões"],
        "mistake": ["Erro", "Erros"], "missed": ["Oportunidade Perdida", "Oportunidades Perdidas"], "blunder": ["Erro Grave", "Erros Graves"]}
    return names[cls][0 if n == 1 else 1]

func _first_of(cls: String, human: String) -> int:
    for m in report.moves:
        if m.class == cls and (human == "" or m.color == human): return m.ply
    return -1

func _trainable(human: String) -> Array:
    var out := []
    for cls in Config.TRAIN_CLASSES:
        for m in report.moves:
            if m.class == cls and (human == "" or m.color == human) and m.ply not in out: out.append(m.ply)
    return out.slice(0, 8)

# ---------------------------------------------------------------- navegação lance a lance
func _goto(ply: int, animate := true):
    if report.is_empty() or page != "report" or trying: return
    ply = clampi(ply, -1, report.moves.size() - 1)
    cur_ply = ply
    showing_best = false
    board.clear_marks()
    if ply < 0:
        board.show_fen(Notation.fen(record.position_after(0)), animate)
    else:
        var m: Dictionary = report.moves[ply]
        var mv := Notation.uci_to_move(String(m.uci))
        board.show_fen(String(m.fen_after), animate, mv.from, mv.to)
    if is_instance_valid(graph): graph.set_selected(ply)
    if is_instance_valid(eval_bar):
        if ply < 0: eval_bar.set_eval(0.2, "")
        else: eval_bar.set_eval(float(report.moves[ply].signed_after), String(report.moves[ply].text_after))
    for i in move_buttons:
        var b: Button = move_buttons[i]
        b.modulate = Color(1.3, 1.25, 1.0) if i == ply else Color.WHITE
        b.add_theme_color_override("font_color", Art.GOLD if i == ply else Art.CREAM)
    _fill_detail()

func _fill_detail():
    for c in detail.get_children():
        detail.remove_child(c)
        c.queue_free()
    var f := preload("res://analysis/analysis_art.gd").panel(22)
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 8)
    f.add_child(v)
    if cur_ply < 0:
        Art.label(v, "POSIÇÃO INICIAL", fs(22), Art.GOLD, Art.FONT_BOLD)
        Art.label(v, "Use < > (ou as setas do teclado), o gráfico ou a lista para percorrer a partida.", fs(15), Art.MUTED)
        return
    var m: Dictionary = report.moves[cur_ply]
    var mine: bool = String(report.human_color) == "" or m.color == report.human_color
    var AA := preload("res://analysis/analysis_art.gd")
    var hl := AA.caps(v, "LANCE %d" % (cur_ply / 2 + 1), fs(15), Art.GOLD)
    hl.name = "DetailPly"
    AA.caps(v, ("VOCÊ JOGOU" if mine else "ADVERSÁRIO JOGOU"), fs(14), Art.MUTED)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    v.add_child(row)
    var sl := AA.big(row, String(m.san), fs(38), Art.CREAM, Color(0.05, 0.03, 0.01, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
    sl.name = "DetailSan"
    sl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    sl.autowrap_mode = TextServer.AUTOWRAP_OFF
    var cls := String(m.class)
    if m.marked: row.add_child(Art.Stamp.new("MARCADO PARA REVISAR", "info", 12))
    var ev := GridContainer.new()
    ev.columns = 2
    ev.add_theme_constant_override("h_separation", 24)
    v.add_child(ev)
    AA.caps(ev, "ANTES", fs(14), Art.MUTED)
    AA.caps(ev, "DEPOIS", fs(14), Art.MUTED)
    var eb := AA.big(ev, String(m.text_before), fs(28), Art.GOLD, Color(0.05, 0.03, 0.01, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
    eb.name = "DetailBefore"
    var ea := AA.big(ev, String(m.text_after), fs(28), Art.GOLD, Color(0.05, 0.03, 0.01, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
    ea.name = "DetailAfter"
    if not String(m.best_san).is_empty() and String(m.best) != String(m.uci):
        AA.caps(v, "MELHOR LANCE", fs(14), Art.MUTED)
        var bl := AA.big(v, String(m.best_san), fs(26), Color("9de5a0"), Color(0.02, 0.06, 0.03, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
        bl.name = "DetailBest"
    var buttons: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 8)
    v.add_child(buttons)
    if not String(m.best).is_empty() and String(m.best) != String(m.uci):
        var vb := Art.Cta.new("VER MELHOR LANCE", "gold", 50, 16)
        vb.name = "ShowBest"
        vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        vb.pressed.connect(_toggle_best)
        buttons.add_child(vb)
    if mine and cls in ["blunder", "mistake", "missed", "inaccuracy"]:
        var tb := Art.Cta.new("TENTAR NOVAMENTE", "green", 50, 16)
        tb.name = "TryAgain"
        tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tb.pressed.connect(_start_try)
        buttons.add_child(tb)
    if not Array(m.pv).is_empty() and String(m.best) != String(m.uci):
        var pv_pos = Notation.from_fen(String(m.fen_before))
        var pv_text := _pv_text(pv_pos, Array(m.pv))
        var pl := Art.label(v, "Linha principal: " + pv_text, fs(14), Art.MUTED)
        pl.name = "DetailPv"

func _pv_text(pos, pv: Array) -> String:
    if pos == null: return ""
    var out := []
    var p = pos.copy_position()
    for u in pv.slice(0, 6):
        var mv := Notation.uci_to_move(String(u))
        if mv.is_empty() or p.piece(mv.from).is_empty(): break
        var san := Notation.san(p, mv)
        out.append(("%d." % (int(p.ply) / 2 + 1) + san) if p.turn == "w" else san)
        if not p.play(mv): break
    return " ".join(out)

## VER MELHOR LANCE: volta à posição antes do lance, seta + casas do melhor lance e a linha principal.
func _toggle_best():
    if cur_ply < 0: return
    var m: Dictionary = report.moves[cur_ply]
    showing_best = not showing_best
    var played := Notation.uci_to_move(String(m.uci))
    if showing_best:
        var bm := Notation.uci_to_move(String(m.best))
        board.show_fen(String(m.fen_before), true)
        board.highlight = {bm.from: Color(0.3, 0.75, 1.0, 0.35), bm.to: Color(0.3, 0.75, 1.0, 0.45)}
        board.set_mark("", "", Color.WHITE)
        var arrows := [{"from": bm.from, "to": bm.to, "color": Color(0.3, 0.75, 1.0, 0.9)}]
        arrows.append({"from": played.from, "to": played.to, "color": Color(1.0, 0.45, 0.35, 0.55)})
        board.set_arrows(arrows)
    else:
        board.clear_marks()
        board.show_fen(String(m.fen_after), true, played.from, played.to)
    var btn = root.find_child("ShowBest", true, false)
    if btn != null: btn.text = "VER LANCE JOGADO" if showing_best else "VER MELHOR LANCE"

# ---------------------------------------------------------------- TENTAR NOVAMENTE
func _start_try():
    if cur_ply < 0 or trying: return
    trying = true
    var m: Dictionary = report.moves[cur_ply]
    for c in detail.get_children():
        detail.remove_child(c)
        c.queue_free()
    board.clear_marks()
    board.show_fen(String(m.fen_before), true)
    board.interactive = true
    board.move_tried.connect(_on_try_move)
    var f := Art.Frame.new("club", 18)
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.add_child(f)
    try_panel = VBoxContainer.new()
    try_panel.add_theme_constant_override("separation", 8)
    f.add_child(try_panel)
    Art.label(try_panel, "TENTAR NOVAMENTE", fs(22), Art.GOLD, Art.FONT_BOLD)
    Art.label(try_panel, "Tabuleiro de treino: a partida original continua intacta. Jogue outro lance no lugar de %s." % m.san, fs(15), Art.CREAM)
    try_status = Art.label(try_panel, "Sua vez. Escolha uma peça.", fs(16), Art.MUTED)
    try_status.name = "TryStatus"
    var back := Art.Cta.new("VOLTAR À REVISÃO", "dark", 46, 15)
    back.name = "TryBack"
    back.pressed.connect(_end_try)
    try_panel.add_child(back)

func _end_try():
    if not trying: return
    trying = false
    board.interactive = false
    if board.move_tried.is_connected(_on_try_move): board.move_tried.disconnect(_on_try_move)
    _goto(cur_ply, false)

func _on_try_move(mv: Dictionary):
    var m: Dictionary = report.moves[cur_ply]
    var pos = Notation.from_fen(String(m.fen_before))
    var uci := Notation.uci_of(pos, mv)
    var san := Notation.san(pos, mv)
    if not pos.play(mv): return
    board.interactive = false
    board.show_fen(Notation.fen(pos), true, mv.from, mv.to)
    try_status.text = "Avaliando %s…" % san
    var r: Dictionary = await engine.evaluate(Notation.fen(pos), analyzer.depth, analyzer.max_ms_per_pos)
    if not trying or not is_instance_valid(try_status): return
    var new_cp := -int(r.get("cp", 0))
    var new_mate := -int(r.get("mate", 0))
    var new_win := Config.win_percent(new_cp, new_mate)
    var orig_win := float(m.win_after)
    var best_win := float(m.win_before)
    var verdict := ""
    var tone := "ok"
    if uci == String(m.best) or new_win >= best_win - Config.EXCELLENT: verdict = "EXCELENTE!"
    elif new_win >= orig_win + 10.0: verdict = "MUITO MELHOR!"
    elif new_win >= orig_win + 3.0: verdict = "BOA IDEIA, MAS EXISTIA UMA OPÇÃO MAIS FORTE."
    else:
        verdict = "TENTE NOVAMENTE."
        tone = "test"
    for c in try_panel.get_children():
        if c.name in ["TryVerdict", "TryGrid", "TryAgainBtn"]:
            try_panel.remove_child(c)
            c.queue_free()
    var vl := Art.Stamp.new(verdict, tone, 15)
    vl.name = "TryVerdict"
    try_panel.add_child(vl)
    try_panel.move_child(vl, 2)
    # Três colunas que dividem a largura (celular: empilha). Labels de uma linha.
    var g: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    g.name = "TryGrid"
    g.add_theme_constant_override("separation", 12)
    g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    try_panel.add_child(g)
    try_panel.move_child(g, 3)
    for pair in [["JOGADA ORIGINAL:", m.text_after, Config.COLORS[m.class]], ["SUA NOVA JOGADA:", Config.eval_text(new_cp, new_mate, m.color), Color("bfe8a8") if tone == "ok" else Color("f2a070")], ["MELHOR POSSÍVEL:", m.text_before, Color("9de5a0")]]:
        var cell := VBoxContainer.new()
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        g.add_child(cell)
        var a := Art.label(cell, pair[0], fs(12), Art.MUTED)
        a.autowrap_mode = TextServer.AUTOWRAP_OFF
        var v2 := Art.label(cell, String(pair[1]), fs(24), pair[2], Art.FONT_BOLD)
        v2.autowrap_mode = TextServer.AUTOWRAP_OFF
    try_status.text = "Você jogou %s." % san
    var again := Art.Cta.new("TENTAR OUTRO LANCE", "green", 46, 15)
    again.name = "TryAgainBtn"
    again.pressed.connect(func():
        board.show_fen(String(m.fen_before), true)
        board.interactive = true
        try_status.text = "Sua vez. Escolha uma peça.")
    try_panel.add_child(again)
    try_panel.move_child(again, 4)
    if tone == "ok": _class_effect("excellent")
    else: _class_effect("mistake")
