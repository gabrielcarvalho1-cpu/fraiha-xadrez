extends CanvasLayer
## TREINE MEUS ERROS — primeira versão: as posições relevantes da análise (erro grave, erro,
## oportunidade perdida, imprecisão) viram exercícios. "EXERCÍCIO 1 DE 5 · ENCONTRE UMA
## CONTINUAÇÃO MELHOR." O jogador joga; a engine avalia; feedback; próximo.
## Não altera PL, estatísticas Ranked nem o resultado original. Tabuleiro separado.
signal closed

const Art := preload("res://monetization/premium_art.gd")
const Config := preload("res://analysis/analysis_config.gd")
const Notation := preload("res://analysis/notation.gd")
const ReviewBoard := preload("res://analysis/review_board.gd")

var engine
var report := {}
var exercises: Array = []     # plies
var index := 0
var root: Control
var column: VBoxContainer
var board: ReviewBoard
var title: Label
var status: Label
var panel: VBoxContainer
var solved := 0
var depth := 12
var max_ms := 1400
var narrow := false

func _init(p_engine):
    layer = 66
    name = "TrainingUI"
    engine = p_engine

func _ready():
    _build()
    get_viewport().size_changed.connect(_relayout)
    visible = false

## CLUB · TREINE MEUS ERROS / TREINO PERSONALIZADO: exercícios vindos de várias partidas do histórico
## (cada item é um lance do relatório, com fen_before/best/win_*; "move_no" = número do lance original).
func open_exercises(moves: Array, max_count := 10):
    var list: Array = []
    for i in moves.size():
        var m: Dictionary = moves[i].duplicate(true)
        m["ply"] = i
        list.append(m)
    open_for({"human_color": "", "moves": list}, max_count)

func open_for(p_report: Dictionary, max_count := 8):
    report = p_report
    var human: String = String(report.human_color)
    exercises.clear()
    for cls in Config.TRAIN_CLASSES:
        for m in report.moves:
            if m.class == cls and (human == "" or m.color == human) and m.ply not in exercises: exercises.append(m.ply)
    exercises = exercises.slice(0, max_count)
    exercises.sort()
    index = 0
    solved = 0
    var prof: Dictionary = preload("res://analysis/analysis_config.gd").engine_profile(engine.transport, true)
    depth = int(prof.depth)
    max_ms = int(prof.max_ms)
    visible = true
    root.visible = true
    _show_exercise()

func close():
    visible = false
    root.visible = false
    closed.emit()

func _input(event):
    if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        close()
        get_viewport().set_input_as_handled()

func _build():
    root = Control.new()
    root.name = "TrainingRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    var bg := ColorRect.new()
    bg.color = Color(0.01, 0.04, 0.025, 1.0)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(bg)
    root.add_child(Art.Sparkles.new(20))
    var outer := VBoxContainer.new()
    outer.name = "TrainingOuter"
    outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    outer.add_theme_constant_override("separation", 8)
    root.add_child(outer)
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    outer.add_child(header)
    var back := Art.Cta.new("VOLTAR", "dark", 48, 16)
    back.name = "TrainingBack"
    back.custom_minimum_size.x = 140
    back.pressed.connect(close)
    header.add_child(back)
    title = Art.label(header, "TREINE MEUS ERROS", 24, Art.GOLD, Art.FONT_BOLD)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    outer.add_child(scroll)
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    var center := CenterContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(center)
    column = VBoxContainer.new()
    column.add_theme_constant_override("separation", 14)
    center.add_child(column)
    _relayout()

func _relayout():
    if root == null: return
    var vs := root.get_viewport_rect().size
    narrow = vs.x < 760.0
    var outer: Control = root.get_node("TrainingOuter")
    var gutter := 14.0 if narrow else 36.0
    outer.offset_left = gutter
    outer.offset_right = -gutter
    outer.offset_top = 12.0
    outer.offset_bottom = -8.0
    column.custom_minimum_size.x = minf(vs.x - gutter * 2.0 - 16.0, 1100.0)

func _clear():
    for c in column.get_children():
        column.remove_child(c)
        c.queue_free()

func _show_exercise():
    _clear()
    if index >= exercises.size():
        _show_done()
        return
    var ply: int = exercises[index]
    var m: Dictionary = report.moves[ply]
    var head := Art.Frame.new("club", 16)
    column.add_child(head)
    var hv := VBoxContainer.new()
    head.add_child(hv)
    var t := Art.label(hv, "EXERCÍCIO %d DE %d" % [index + 1, exercises.size()], 22, Art.GOLD, Art.FONT_BOLD)
    t.name = "ExerciseTitle"
    Art.label(hv, "ENCONTRE UMA CONTINUAÇÃO MELHOR.", 18, Art.CREAM, Art.FONT_SEMI)
    Art.label(hv, "Na partida você jogou %s. Lance %d · %s jogam." % [m.san, int(m.get("move_no", ply / 2 + 1)), "Brancas" if m.color == "w" else "Pretas"], 14, Art.MUTED)
    var row: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 18)
    column.add_child(row)
    board = ReviewBoard.new()
    board.name = "TrainingBoard"
    var side := minf(column.custom_minimum_size.x - 8.0, 420.0) if narrow else 500.0
    board.custom_minimum_size = Vector2(side, side)
    board.flipped = m.color == "b"
    board.show_fen(String(m.fen_before), false)
    board.interactive = true
    board.move_tried.connect(_on_move)
    row.add_child(board)
    var f := Art.Frame.new("dark", 16)
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(f)
    panel = VBoxContainer.new()
    panel.add_theme_constant_override("separation", 8)
    f.add_child(panel)
    status = Art.label(panel, "Sua vez. Escolha uma peça e a casa de destino.", 16, Art.MUTED)
    status.name = "TrainingStatus"
    var skip := Art.Cta.new("PULAR", "dark", 44, 15)
    skip.name = "TrainingSkip"
    skip.pressed.connect(_next)
    panel.add_child(skip)

func _on_move(mv: Dictionary):
    var ply: int = exercises[index]
    var m: Dictionary = report.moves[ply]
    var pos = Notation.from_fen(String(m.fen_before))
    var uci := Notation.uci_of(pos, mv)
    var san := Notation.san(pos, mv)
    if not pos.play(mv): return
    board.interactive = false
    board.show_fen(Notation.fen(pos), true, mv.from, mv.to)
    status.text = "Avaliando %s…" % san
    var r: Dictionary = await engine.evaluate(Notation.fen(pos), depth, max_ms)
    if not visible or not is_instance_valid(status): return
    var new_win := Config.win_percent(-int(r.get("cp", 0)), -int(r.get("mate", 0)))
    var orig_win := float(m.win_after)
    var best_win := float(m.win_before)
    var verdict := "TENTE NOVAMENTE."
    var tone := "test"
    var ok := false
    if uci == String(m.best) or new_win >= best_win - Config.EXCELLENT:
        verdict = "EXCELENTE!"
        tone = "ok"
        ok = true
    elif new_win >= orig_win + 10.0:
        verdict = "MUITO MELHOR."
        tone = "ok"
        ok = true
    elif new_win >= orig_win + 3.0:
        verdict = "BOA IDEIA, MAS EXISTIA UMA OPÇÃO MAIS FORTE."
        tone = "info"
    for c in panel.get_children():
        if c.name in ["Verdict", "VerdictGrid", "NextBtn", "RetryBtn"]:
            panel.remove_child(c)
            c.queue_free()
    var vl := Art.Stamp.new(verdict, tone, 15)
    vl.name = "Verdict"
    panel.add_child(vl)
    panel.move_child(vl, 1)
    var g: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    g.name = "VerdictGrid"
    g.add_theme_constant_override("separation", 12)
    g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.add_child(g)
    panel.move_child(g, 2)
    for pair in [["NA PARTIDA:", m.text_after, Config.COLORS[m.class]], ["AGORA:", Config.eval_text(-int(r.get("cp", 0)), -int(r.get("mate", 0)), m.color), Color("bfe8a8") if ok else Color("f2a070")], ["MELHOR:", m.text_before, Color("9de5a0")]]:
        var cell := VBoxContainer.new()
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        g.add_child(cell)
        Art.label(cell, pair[0], 12, Art.MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
        Art.label(cell, String(pair[1]), 22, pair[2], Art.FONT_BOLD).autowrap_mode = TextServer.AUTOWRAP_OFF
    status.text = "Você jogou %s." % san
    if ok:
        solved += 1
        preload("res://analysis/club_insights.gd").add_training_solved(1)   # Desafio Club "TREINO EM DIA"
        var nb := Art.Cta.new("PRÓXIMO EXERCÍCIO" if index + 1 < exercises.size() else "CONCLUIR", "green", 46, 15)
        nb.name = "NextBtn"
        nb.pressed.connect(_next)
        panel.add_child(nb)
        panel.move_child(nb, 3)
        var burst := Art.Sparkles.new(40, Color("9de5a0"))
        board.add_child(burst)
        var tw := create_tween()
        tw.tween_interval(1.4)
        tw.tween_callback(func(): if is_instance_valid(burst): burst.queue_free())
    else:
        var rb := Art.Cta.new("TENTAR NOVAMENTE", "gold", 46, 15)
        rb.name = "RetryBtn"
        rb.pressed.connect(func():
            board.show_fen(String(m.fen_before), true)
            board.interactive = true
            status.text = "Sua vez. Escolha uma peça.")
        panel.add_child(rb)
        panel.move_child(rb, 3)

func _next():
    index += 1
    _show_exercise()

func _show_done():
    var f := Art.Frame.new("founder", 26)
    f.name = "TrainingDone"
    column.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    f.add_child(v)
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(row)
    row.add_child(Art.Glyph.new("trophy", 64, Art.GOLD, true))
    Art.label(v, "TREINO CONCLUÍDO", 28, Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, "%d de %d posições resolvidas com uma continuação melhor." % [solved, exercises.size()], 18, Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, "Nada disto altera PL, estatísticas Ranked ou o resultado original.", 13, Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    var b := Art.Cta.new("VOLTAR À ANÁLISE", "gold", 54, 18)
    b.name = "TrainingFinish"
    b.pressed.connect(close)
    v.add_child(b)
