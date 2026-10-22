extends CanvasLayer
## TREINE MEUS ERROS (R169: ajuda em 3 degraus, estrelas e limite diário como a análise): as posições relevantes da análise (erro grave, erro,
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
var quota_label: Label

func _init(p_engine):
    layer = 66
    preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC em tudo (fecha só a janela de cima)
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
    stars_total = 0
    var prof: Dictionary = preload("res://analysis/analysis_config.gd").engine_profile(engine.transport, true)
    depth = int(prof.depth)
    max_ms = int(prof.max_ms)
    visible = true
    root.visible = true
    var acc = get_parent().get("training_access") if get_parent() != null else null
    if quota_label != null: quota_label.text = "" if acc == null else ("TREINOS: ILIMITADO" if acc.club_unlimited() else "TREINOS GRÁTIS HOJE  %d / %d" % [int(acc.used), int(acc.limit)])
    _show_exercise()

func close():
    visible = false
    root.visible = false
    closed.emit()

func esc_open() -> bool:
    return visible

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
    bg.color = Color(0.014, 0.029, 0.057, 1.0)
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
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    title.clip_text = true
    title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    quota_label = Art.label(header, "", 14, Art.GOLD, Art.FONT_SEMI)   # R169 · "TREINOS GRÁTIS HOJE 1/3" como na análise
    quota_label.name = "TrainingQuota"
    quota_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    quota_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
    # R176 · PC/navegador: a tela inteira cresce junto com a janela (antes ficava minúscula num monitor grande).
    # Tudo é montado em "unidades" de uma tela 1280 x 760 e ampliado por k; celular em pé continua 1:1.
    var k := 1.0 if narrow else clampf(minf(vs.x / 1280.0, vs.y / 760.0), 1.0, 2.4)
    outer.set_anchors_preset(Control.PRESET_TOP_LEFT)
    outer.scale = Vector2(k, k)
    outer.position = Vector2(gutter, 12.0)
    outer.size = Vector2(vs.x - gutter * 2.0, vs.y - 20.0) / k
    column.custom_minimum_size.x = minf(outer.size.x - 16.0, 1100.0)
    if title != null: title.add_theme_font_size_override("font_size", 17 if narrow else 24)

func _clear():
    for c in column.get_children():
        column.remove_child(c)
        c.queue_free()

## R169 · TREINE SEUS ERROS mais claro: a seta vermelha mostra o lance da partida; ajuda em 3 degraus
## (DICA acende a peça certa, MOSTRAR LANCE desenha a seta verde e joga o lance, PRÓXIMO pula) e estrelas:
## acertar sem ajuda ⭐⭐⭐, com DICA ⭐⭐, depois de ver o lance ⭐. Errou: diz o porquê e a peça volta sozinha.
var stars_total := 0
var hint_used := false
var shown := false
var attempts := 0
var stars_row: HBoxContainer
var help_row: BoxContainer
var hint_btn
var show_btn
var next_btn
var info_box: VBoxContainer

func _cur() -> Dictionary:
    return report.moves[exercises[index]]

func _uci_move(uci: String) -> Dictionary:
    return Notation.uci_to_move(uci) if uci.length() >= 4 else {}

func _show_exercise():
    _clear()
    if index >= exercises.size():
        _show_done()
        return
    hint_used = false
    shown = false
    attempts = 0
    var ply: int = exercises[index]
    var m: Dictionary = report.moves[ply]
    var head := Art.Frame.new("club", 16)
    column.add_child(head)
    var hv := VBoxContainer.new()
    hv.add_theme_constant_override("separation", 4)
    head.add_child(hv)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 10)
    hv.add_child(top)
    var t := Art.label(top, "EXERCÍCIO %d DE %d" % [index + 1, exercises.size()], 22, Art.GOLD, Art.FONT_BOLD)
    t.name = "ExerciseTitle"
    t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    stars_row = HBoxContainer.new()
    stars_row.name = "TrainingStarsTotal"
    stars_row.add_theme_constant_override("separation", 4)
    top.add_child(stars_row)
    var sg := Art.Glyph.new("star", 26, Art.GOLD)
    sg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    stars_row.add_child(sg)
    var sl := Art.label(stars_row, "%d" % stars_total, 22, Art.GOLD, Art.FONT_BOLD)
    sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    sl.autowrap_mode = TextServer.AUTOWRAP_OFF
    var lead := Art.label(hv, "Na partida você jogou %s (seta vermelha). Existe um lance melhor: ache!" % String(m.san), 19, Art.CREAM, Art.FONT_SEMI)
    lead.name = "ExerciseLead"
    lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    Art.label(hv, "Lance %d · %s jogam" % [int(m.get("move_no", ply / 2 + 1)), "Brancas" if m.color == "w" else "Pretas"], 14, Art.MUTED)
    if quota_label != null:
        quota_label.visible = not narrow   # celular: o contador vem aqui embaixo (no topo não cabe)
        if narrow and not quota_label.text.is_empty(): Art.label(hv, quota_label.text, 12, Art.GOLD, Art.FONT_SEMI)
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
    _played_arrow()
    var f := Art.Frame.new("dark", 16)
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(f)
    panel = VBoxContainer.new()
    panel.add_theme_constant_override("separation", 10)
    f.add_child(panel)
    status = Art.label(panel, "Sua vez: toque numa peça e depois na casa.", 17, Art.CREAM)
    status.name = "TrainingStatus"
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # placar simples: o que a partida deu x o que dava
    var cmp := HBoxContainer.new()
    cmp.name = "TrainingCompare"
    cmp.add_theme_constant_override("separation", 10)
    panel.add_child(cmp)
    _pill(cmp, "NA PARTIDA", String(m.text_after), Color("f2a070"))
    _pill(cmp, "O MELHOR DAVA", String(m.text_before), Color("9de5a0"))
    info_box = VBoxContainer.new()
    info_box.name = "TrainingInfo"
    info_box.add_theme_constant_override("separation", 6)
    panel.add_child(info_box)
    Art.label(panel, "PRECISA DE AJUDA?", 13, Art.MUTED, Art.FONT_SEMI)
    help_row = VBoxContainer.new() if narrow else HBoxContainer.new()
    help_row.name = "TrainingHelp"
    help_row.add_theme_constant_override("separation", 8)
    panel.add_child(help_row)
    hint_btn = Art.Cta.new("DICA", "dark", 46, 15)
    hint_btn.name = "TrainingHint"
    hint_btn.icon_kind = "magnifier"
    hint_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hint_btn.tooltip_text = "Acende a peça que deve se mexer (vale 2 estrelas)"
    hint_btn.pressed.connect(_hint)
    help_row.add_child(hint_btn)
    show_btn = Art.Cta.new("MOSTRAR LANCE", "dark", 46, 15)
    show_btn.name = "TrainingShow"
    show_btn.icon_kind = "target"
    show_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    show_btn.tooltip_text = "Mostra e joga o melhor lance (vale 1 estrela)"
    show_btn.pressed.connect(_show_best)
    help_row.add_child(show_btn)
    next_btn = Art.Cta.new("PRÓXIMO", "dark", 46, 15)
    next_btn.name = "TrainingSkip"
    next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    next_btn.pressed.connect(_next)
    help_row.add_child(next_btn)
    var legend := Art.label(panel, "Acertar sozinho: 3 estrelas · com DICA: 2 · depois de ver o lance: 1", 12, Art.MUTED)
    legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _pill(parent: Control, cap: String, val: String, col: Color):
    var cell := VBoxContainer.new()
    cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cell.add_theme_constant_override("separation", 0)
    parent.add_child(cell)
    Art.label(cell, cap, 12, Art.MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
    Art.label(cell, val, 24, col, Art.FONT_BOLD).autowrap_mode = TextServer.AUTOWRAP_OFF

## seta vermelha: o lance que foi jogado na partida
func _played_arrow():
    var m := _cur()
    var mv := _uci_move(String(m.get("uci", "")))
    var list: Array = []
    if not mv.is_empty(): list.append({"from": mv.from, "to": mv.to, "color": Color(0.92, 0.28, 0.22, 0.8)})
    if shown:
        var bm := _uci_move(String(m.get("best", "")))
        if not bm.is_empty(): list.append({"from": bm.from, "to": bm.to, "color": Color(0.35, 0.86, 0.45, 0.9)})
    board.set_arrows(list)
    board.highlight.clear()
    if hint_used and not shown:
        var bm2 := _uci_move(String(m.get("best", "")))
        if not bm2.is_empty(): board.highlight[bm2.from] = Color(1.0, 0.78, 0.1, 0.8)
    board.queue_redraw()

func _hint():
    if shown: return
    hint_used = true
    _played_arrow()
    status.text = "DICA: a peça que acendeu em amarelo é a que deve se mexer."
    hint_btn.disabled = true

func _show_best():
    if shown: return
    var m := _cur()
    var bm := _uci_move(String(m.get("best", "")))
    if bm.is_empty(): return
    shown = true
    board.interactive = false
    hint_btn.disabled = true
    show_btn.disabled = true
    var pos = Notation.from_fen(String(m.fen_before))
    var nice := String(m.get("best_san", "")) if String(m.get("best_san", "")) != "" else Notation.san(pos, bm)
    board.show_fen(String(m.fen_before), false)
    _played_arrow()
    status.text = "O melhor lance era %s (seta verde)." % nice
    await get_tree().create_timer(0.9).timeout
    if not visible or not is_instance_valid(board): return
    if pos.play(bm): board.show_fen(Notation.fen(pos), true, bm.from, bm.to)
    _award(1, "Agora você viu: %s. Na próxima, tente achar sozinho!" % nice)

func _award(n: int, msg: String):
    for c in info_box.get_children(): c.queue_free()
    stars_total += n
    solved += 1 if n >= 2 else 0
    if n >= 2: preload("res://analysis/club_insights.gd").add_training_solved(1)   # Desafio Club "TREINO EM DIA"
    var sr := HBoxContainer.new()
    sr.name = "TrainingStars"
    sr.add_theme_constant_override("separation", 6)
    info_box.add_child(sr)
    for i in 3: sr.add_child(Art.Glyph.new("star", 34, Art.GOLD if i < n else Color(0.35, 0.33, 0.28)))
    var l := Art.label(info_box, msg, 16, Color("bfe8a8") if n >= 2 else Art.CREAM)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint_btn.disabled = true
    show_btn.disabled = true
    next_btn.text = "PRÓXIMO EXERCÍCIO" if index + 1 < exercises.size() else "VER RESULTADO"
    next_btn.style = "green"
    next_btn.queue_redraw()
    for c in stars_row.get_children():
        if c is Label: c.text = "%d" % stars_total

## por que o lance não serve (pela avaliação da engine, em palavras simples)
func _why(new_win: float, orig_win: float, best_win: float, mate: int) -> String:
    if mate < 0: return "Esse lance permite um xeque-mate contra você."
    if new_win < orig_win - 3.0: return "Esse lance é ainda pior que o da partida: perde material ou deixa o rei exposto."
    if new_win < orig_win + 3.0: return "Esse lance dá quase o mesmo resultado do que você jogou na partida."
    return "Melhorou, mas ainda existe um lance mais forte."

func _on_move(mv: Dictionary):
    var m := _cur()
    var pos = Notation.from_fen(String(m.fen_before))
    var uci := Notation.uci_of(pos, mv)
    var san := Notation.san(pos, mv)
    if not pos.play(mv): return
    attempts += 1
    board.interactive = false
    board.set_arrows([])
    board.show_fen(Notation.fen(pos), true, mv.from, mv.to)
    status.text = "Avaliando %s…" % san
    var r: Dictionary = await engine.evaluate(Notation.fen(pos), depth, max_ms)
    if not visible or not is_instance_valid(status): return
    var new_win := Config.win_percent(-int(r.get("cp", 0)), -int(r.get("mate", 0)))
    var orig_win := float(m.win_after)
    var best_win := float(m.win_before)
    var ok: bool = uci == String(m.best) or new_win >= best_win - Config.EXCELLENT or new_win >= orig_win + 10.0
    if ok:
        status.text = "%s · %s" % [san, "EXCELENTE!" if (uci == String(m.best) or new_win >= best_win - Config.EXCELLENT) else "MUITO MELHOR!"]
        _award(2 if hint_used else 3, "Você achou%s! Agora: %s." % [" com a dica" if hint_used else " sozinho", Config.eval_text(-int(r.get("cp", 0)), -int(r.get("mate", 0)), m.color)])
        var burst := Art.Sparkles.new(40, Color("9de5a0"))
        board.add_child(burst)
        var tw := create_tween()
        tw.tween_interval(1.4)
        tw.tween_callback(func(): if is_instance_valid(burst): burst.queue_free())
        return
    # errou: explica, mostra o número e devolve a peça sozinha
    for c in info_box.get_children(): c.queue_free()
    var why := Art.label(info_box, "%s não serve. %s" % [san, _why(new_win, orig_win, best_win, -int(r.get("mate", 0)))], 16, Color("f2a070"))
    why.name = "TrainingWhy"
    why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    Art.label(info_box, "Com %s ficaria: %s" % [san, Config.eval_text(-int(r.get("cp", 0)), -int(r.get("mate", 0)), m.color)], 14, Art.MUTED)
    if attempts >= 2 and not hint_used: Art.label(info_box, "Travou? Toque em DICA.", 14, Art.GOLD)
    status.text = "Tente outro lance."
    await get_tree().create_timer(1.3).timeout
    if not visible or not is_instance_valid(board) or shown: return
    board.show_fen(String(m.fen_before), true)
    _played_arrow()
    board.interactive = true

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
    var sr := HBoxContainer.new()
    sr.name = "TrainingDoneStars"
    sr.alignment = BoxContainer.ALIGNMENT_CENTER
    sr.add_theme_constant_override("separation", 8)
    v.add_child(sr)
    sr.add_child(Art.Glyph.new("star", 40, Art.GOLD))
    Art.label(sr, "%d de %d estrelas" % [stars_total, exercises.size() * 3], 26, Art.GOLD, Art.FONT_BOLD)
    Art.label(v, "Você acertou %d de %d posições (sozinho ou com dica)." % [solved, exercises.size()], 18, Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, "Nada disto altera PL, estatísticas Ranked ou o resultado original.", 13, Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    var b := Art.Cta.new("VOLTAR À ANÁLISE", "gold", 54, 18)
    b.name = "TrainingFinish"
    b.pressed.connect(close)
    v.add_child(b)
