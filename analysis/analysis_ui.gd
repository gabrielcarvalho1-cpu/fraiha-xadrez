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

var engine
var analyzer
var access
var hub                       # main_hub (Premium, entitlements)
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
    analyzer.depth = 14 if engine.transport != "builtin" else 7
    analyzer.max_ms_per_pos = 1600 if engine.transport != "builtin" else 500
    var rep: Dictionary = await analyzer.analyze(record)
    if rep.is_empty() or not visible: return
    report = rep
    _show_page("report")

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
        bg.draw_rect(Rect2(Vector2.ZERO, bg.size), Color(0.01, 0.04, 0.025, 1.0))
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
    back_button.pressed.connect(func():
        if trying: _end_try()
        else: close())
    header.add_child(back_button)
    header_label = Art.label(header, "ANÁLISE DA PARTIDA", 24, Art.GOLD, Art.FONT_BOLD)
    header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var quota_tag := Art.Stamp.new("", "info", 13)
    quota_tag.name = "QuotaTag"
    header.add_child(quota_tag)
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
func _page_progress():
    var f := Art.Frame.new("club", 24)
    f.name = "ProgressPanel"
    column.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    f.add_child(v)
    var t := Art.label(v, "ANALISANDO SUA PARTIDA...", fs(30), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    t.name = "ProgressTitle"
    var layout: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    layout.add_theme_constant_override("separation", 20)
    v.add_child(layout)
    progress_board = ReviewBoard.new()
    progress_board.custom_minimum_size = Vector2(300, 300) * (1.0 if narrow else 1.3)
    progress_board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    progress_board.flipped = String(record.human_color) == "b"
    progress_board.show_fen(Notation.fen(record.position_after(0)), false)
    layout.add_child(progress_board)
    var side := VBoxContainer.new()
    side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    side.add_theme_constant_override("separation", 10)
    layout.add_child(side)
    progress_label = Art.label(side, "LANCE 0 DE %d" % record.moves.size(), fs(24), Art.CREAM, Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    progress_label.name = "ProgressLabel"
    progress_bar = ProgressBar.new()
    progress_bar.name = "ProgressBar"
    progress_bar.max_value = maxi(1, record.moves.size())
    progress_bar.value = 0
    progress_bar.show_percentage = false
    progress_bar.custom_minimum_size.y = 18
    var bgs := StyleBoxFlat.new()
    bgs.bg_color = Color(0.03, 0.08, 0.05)
    bgs.border_color = Color("c99a45")
    bgs.set_border_width_all(1)
    bgs.set_corner_radius_all(6)
    var fgs := StyleBoxFlat.new()
    fgs.bg_color = Color("e9c46a")
    fgs.set_corner_radius_all(6)
    progress_bar.add_theme_stylebox_override("background", bgs)
    progress_bar.add_theme_stylebox_override("fill", fgs)
    side.add_child(progress_bar)
    var feed := VBoxContainer.new()
    feed.name = "ProgressFeed"
    feed.add_theme_constant_override("separation", 4)
    side.add_child(feed)
    Art.label(side, "Motor: %s · profundidade %d" % [engine.engine_name, analyzer.depth], fs(13), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    var cancel := Art.Cta.new("CANCELAR", "ember", 52, 18)
    cancel.name = "AnalysisCancel"
    cancel.pressed.connect(close)
    side.add_child(cancel)

func _on_progress(done: int, total: int, m: Dictionary):
    if page != "progress": return
    if is_instance_valid(progress_label): progress_label.text = "LANCE %d DE %d" % [done, total]
    if is_instance_valid(progress_bar):
        var tw := create_tween()
        tw.tween_property(progress_bar, "value", float(done), 0.25)
    if is_instance_valid(progress_board):
        var mv := Notation.uci_to_move(String(m.uci))
        progress_board.show_fen(String(m.fen_after), true, mv.from, mv.to)
        var cls := String(m.class)
        if cls in ["best", "excellent", "brilliant", "legendary", "mistake", "blunder", "missed"]:
            progress_board.set_mark(cls, Config.GLYPHS[cls], Config.COLORS[cls])
            _class_effect(cls)
        else:
            progress_board.set_mark("", "", Color.WHITE)
    var feed = root.find_child("ProgressFeed", true, false)
    if feed != null:
        var l := Art.label(feed, "%d. %s  %s %s" % [int(m.ply) / 2 + 1, m.san, Config.GLYPHS[m.class], Config.LABELS[m.class]], fs(15), Config.COLORS[m.class])
        l.modulate.a = 0.0
        var tw2 := create_tween()
        tw2.tween_property(l, "modulate:a", 1.0, 0.3)
        while feed.get_child_count() > 6:
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
    # Resumo
    var sum := Art.Frame.new("parchment", 22)
    sum.name = "SummaryPanel"
    column.add_child(sum)
    var sv := VBoxContainer.new()
    sv.add_theme_constant_override("separation", 10)
    sum.add_child(sv)
    var title_row := HBoxContainer.new()
    title_row.add_theme_constant_override("separation", 10)
    sv.add_child(title_row)
    title_row.add_child(Art.Glyph.new("scroll", 34, Art.INK))
    var tl := Art.label(title_row, "SUA PARTIDA", fs(26), Art.INK, Art.FONT_BOLD)
    tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var res: String = {"win": "VITÓRIA", "loss": "DERROTA", "draw": "EMPATE"}.get(String(report.result), "")
    if res != "": title_row.add_child(Art.Stamp.new(res, "ok" if report.result == "win" else ("test" if report.result == "loss" else "soon"), 13))
    var acc_row: BoxContainer = HBoxContainer.new()
    acc_row.add_theme_constant_override("separation", 26)
    sv.add_child(acc_row)
    for pair in [["VOCÊ", me, "AccuracyMe"], ["ADVERSÁRIO", opp, "AccuracyOpp"]]:
        var cell := VBoxContainer.new()
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        acc_row.add_child(cell)
        Art.label(cell, pair[0], fs(13), Art.INK.lightened(0.25), Art.FONT_SEMI)
        Art.label(cell, "PRECISÃO", fs(12), Art.INK.lightened(0.35))
        var al := Art.label(cell, "%.1f%%" % float(pair[1].get("accuracy", 0.0)), fs(40), Art.INK, Art.FONT_BOLD)
        al.name = pair[2]
        al.text = al.text.replace(".", ",")
    var counts: Dictionary = me.get("counts", {})
    var chips := HFlowContainer.new()
    chips.add_theme_constant_override("h_separation", 8)
    chips.add_theme_constant_override("v_separation", 6)
    sv.add_child(chips)
    for cls in ["legendary", "brilliant", "best", "excellent", "good", "book", "inaccuracy", "mistake", "missed", "blunder"]:
        var n := int(counts.get(cls, 0))
        if n == 0: continue
        var chip := Button.new()
        chip.text = "%s %d %s" % [Config.GLYPHS[cls], n, _plural(cls, n)]
        chip.focus_mode = Control.FOCUS_NONE
        chip.add_theme_font_size_override("font_size", fs(14))
        var st := StyleBoxFlat.new()
        st.bg_color = Color(0.1, 0.16, 0.1, 0.9)
        st.border_color = Config.COLORS[cls]
        st.set_border_width_all(1)
        st.set_corner_radius_all(8)
        st.content_margin_left = 10
        st.content_margin_right = 10
        chip.add_theme_stylebox_override("normal", st)
        chip.add_theme_stylebox_override("hover", st)
        chip.add_theme_stylebox_override("pressed", st)
        chip.add_theme_color_override("font_color", Config.COLORS[cls])
        chip.pressed.connect(func(): _goto(_first_of(cls, human)))
        chips.add_child(chip)
    var moments: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    moments.add_theme_constant_override("separation", 20)
    sv.add_child(moments)
    for pair in [["MELHOR MOMENTO", int(me.get("best_moment", -1)), "star"], ["PONTO CRÍTICO", int(me.get("critical", -1)), "target"]]:
        var ply: int = int(pair[1])
        if ply < 0: continue
        var b := Button.new()
        b.flat = true
        b.focus_mode = Control.FOCUS_NONE
        b.pressed.connect(func(): _goto(ply))
        moments.add_child(b)
        var hb := HBoxContainer.new()
        hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hb.add_theme_constant_override("separation", 8)
        b.add_child(hb)
        hb.add_child(Art.Glyph.new(pair[2], 30, Art.INK))
        var col := VBoxContainer.new()
        col.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hb.add_child(col)
        Art.label(col, pair[0], fs(12), Art.INK.lightened(0.3))
        var mv: Dictionary = report.moves[ply]
        Art.label(col, "Lance %d · %s" % [ply / 2 + 1, mv.san], fs(18), Art.INK, Art.FONT_BOLD)
        b.custom_minimum_size = Vector2(240, 48)
    # Gráfico
    var gf := Art.Frame.new("dark", 14)
    gf.name = "GraphPanel"
    column.add_child(gf)
    var gv := VBoxContainer.new()
    gv.add_theme_constant_override("separation", 6)
    gf.add_child(gv)
    Art.label(gv, "AVALIAÇÃO AO LONGO DA PARTIDA", fs(15), Art.GOLD, Art.FONT_SEMI)
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
    var side_px := minf(column.custom_minimum_size.x - 8.0, 420.0) if narrow else 520.0
    board.custom_minimum_size = Vector2(side_px, side_px)
    board.flipped = human == "b"
    left.add_child(board)
    var nav := HBoxContainer.new()
    nav.add_theme_constant_override("separation", 6)
    left.add_child(nav)
    for pair in [["⏮", -999, "NavFirst"], ["◀", -1, "NavPrev"], ["▶", 1, "NavNext"], ["⏭", 999, "NavLast"]]:
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
    # Lista de lances
    var lf := Art.Frame.new("dark", 12)
    lf.name = "MoveListPanel"
    column.add_child(lf)
    var lv := VBoxContainer.new()
    lf.add_child(lv)
    Art.label(lv, "LANCES", fs(15), Art.GOLD, Art.FONT_SEMI)
    var grid := GridContainer.new()
    grid.columns = 2 if narrow else 4
    grid.add_theme_constant_override("h_separation", 6)
    grid.add_theme_constant_override("v_separation", 3)
    lv.add_child(grid)
    move_list = lv
    for i in report.moves.size():
        var m: Dictionary = report.moves[i]
        var b := Button.new()
        b.name = "Move_%d" % i
        b.focus_mode = Control.FOCUS_NONE
        var who := "%d." % (i / 2 + 1) if m.color == "w" else "%d…" % (i / 2 + 1)
        b.text = "%s %s %s" % [who, m.san, Config.GLYPHS[m.class] if m.class not in ["good", "book"] else ""]
        if m.marked: b.text += "  🔖"
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.add_theme_font_size_override("font_size", fs(14))
        b.add_theme_color_override("font_color", Config.COLORS[m.class] if m.class not in ["good", "book"] else Art.CREAM)
        var st := StyleBoxFlat.new()
        st.bg_color = Color(0.05, 0.1, 0.07, 0.8) if m.color == human else Color(0.03, 0.06, 0.05, 0.6)
        st.set_corner_radius_all(4)
        st.content_margin_left = 8
        b.add_theme_stylebox_override("normal", st)
        var hv := st.duplicate()
        hv.bg_color = Color(0.12, 0.22, 0.14, 0.95)
        b.add_theme_stylebox_override("hover", hv)
        b.add_theme_stylebox_override("pressed", hv)
        var idx: int = i
        b.pressed.connect(func(): _goto(idx))
        grid.add_child(b)
        move_buttons[i] = b
    # Treine meus erros
    var trainable := _trainable(human)
    var tf := Art.Frame.new("club", 20)
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
        if m.class not in ["good", "book"]: board.set_mark(m.class, Config.GLYPHS[m.class], Config.COLORS[m.class])
        if animate: _class_effect(String(m.class))
    if is_instance_valid(graph): graph.set_selected(ply)
    for i in move_buttons:
        var b: Button = move_buttons[i]
        b.modulate = Color(1.3, 1.25, 1.0) if i == ply else Color.WHITE
    _fill_detail()

func _fill_detail():
    for c in detail.get_children():
        detail.remove_child(c)
        c.queue_free()
    var f := Art.Frame.new("dark", 18)
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 8)
    f.add_child(v)
    if cur_ply < 0:
        Art.label(v, "POSIÇÃO INICIAL", fs(22), Art.GOLD, Art.FONT_BOLD)
        Art.label(v, "Use ◀ ▶ (ou as setas do teclado), o gráfico ou a lista para percorrer a partida.", fs(15), Art.MUTED)
        return
    var m: Dictionary = report.moves[cur_ply]
    var mine: bool = String(report.human_color) == "" or m.color == report.human_color
    var hl := Art.label(v, "LANCE %d" % (cur_ply / 2 + 1), fs(14), Art.MUTED, Art.FONT_SEMI)
    hl.name = "DetailPly"
    Art.label(v, ("VOCÊ JOGOU:" if mine else "ADVERSÁRIO JOGOU:"), fs(13), Art.MUTED)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    v.add_child(row)
    var sl := Art.label(row, String(m.san), fs(34), Art.CREAM, Art.FONT_BOLD)
    sl.name = "DetailSan"
    sl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    sl.autowrap_mode = TextServer.AUTOWRAP_OFF
    var cls := String(m.class)
    var stamp := Art.Stamp.new(Config.GLYPHS[cls] + " " + Config.LABELS[cls], "ok" if cls in ["best", "excellent", "brilliant", "legendary", "good", "book"] else "test", 13)
    stamp.name = "DetailClass"
    row.add_child(stamp)
    if m.marked: row.add_child(Art.Stamp.new("MARCADO PARA REVISAR", "info", 12))
    var ev := GridContainer.new()
    ev.columns = 2
    ev.add_theme_constant_override("h_separation", 24)
    v.add_child(ev)
    Art.label(ev, "ANTES", fs(13), Art.MUTED)
    Art.label(ev, "DEPOIS", fs(13), Art.MUTED)
    var eb := Art.label(ev, String(m.text_before), fs(26), Art.GOLD, Art.FONT_BOLD)
    eb.name = "DetailBefore"
    var ea := Art.label(ev, String(m.text_after), fs(26), Config.COLORS[cls], Art.FONT_BOLD)
    ea.name = "DetailAfter"
    if not String(m.best_san).is_empty() and String(m.best) != String(m.uci):
        Art.label(v, "MELHOR:", fs(13), Art.MUTED)
        var bl := Art.label(v, String(m.best_san), fs(24), Color("9de5a0"), Art.FONT_BOLD)
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
        if m.class not in ["good", "book"]: board.set_mark(m.class, Config.GLYPHS[m.class], Config.COLORS[m.class])
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
    var g := GridContainer.new()
    g.name = "TryGrid"
    g.columns = 3
    g.add_theme_constant_override("h_separation", 16)
    try_panel.add_child(g)
    try_panel.move_child(g, 3)
    for pair in [["JOGADA ORIGINAL:", m.text_after, Config.COLORS[m.class]], ["SUA NOVA JOGADA:", Config.eval_text(new_cp, new_mate, m.color), Color("bfe8a8") if tone == "ok" else Color("f2a070")], ["MELHOR POSSÍVEL:", m.text_before, Color("9de5a0")]]:
        var cell := VBoxContainer.new()
        g.add_child(cell)
        Art.label(cell, pair[0], fs(12), Art.MUTED)
        Art.label(cell, String(pair[1]), fs(24), pair[2], Art.FONT_BOLD)
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
