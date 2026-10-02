extends RefCounted
## R31 · MEU CLUB — o painel do membro do Club FRAIHA com dados REAIS das suas análises:
##   RELATÓRIO SEMANAL · ESTATÍSTICAS AVANÇADAS · DESAFIOS CLUB · TREINOS (meus erros + personalizado)
##   · HISTÓRICO DETALHADO (rever cada análise).
## Fonte: analysis_history (aparelho; o resumo também vai para a conta). Exclusivo do Club (servidor
## ou simulação). Análise é sempre pós-partida: nada aqui toca em partida em andamento, PL ou Ranked.
const Art := preload("res://monetization/premium_art.gd")
const Insights := preload("res://analysis/club_insights.gd")
const Config := preload("res://analysis/analysis_config.gd")

static func _stage(hub):
    return hub.main_hub.get_parent() if hub.main_hub != null else null

static func history(hub):
    var st = _stage(hub)
    return st.get("analysis_history") if st != null else null

static func entries(hub) -> Array:
    var h = history(hub)
    return h.entries if h != null else []

static func now() -> int:
    return int(Time.get_unix_time_from_system())

static func build(hub, parent: VBoxContainer):
    var head := Art.Frame.new("club", int(26 * hub.k))
    head.name = "MyClubHero"
    head.glow = hub.club_owned()
    parent.add_child(head)
    var hv := VBoxContainer.new()
    hv.add_theme_constant_override("separation", 6)
    head.add_child(hv)
    var t := Art.label(hv, "MEU CLUB", hub.fs(46), Art.GOLD, Art.FONT_BOLD)
    t.add_theme_constant_override("outline_size", 8)
    t.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.05, 0.95))
    Art.label(hv, "JOGUE.  ENTENDA.  EVOLUA.", hub.fs(22), Color("bfe8a8"), Art.FONT_BOLD)
    if not hub.club_owned():
        Art.label(hv, "Estatísticas avançadas, relatório semanal, histórico detalhado, treinos e desafios são exclusivos do Club FRAIHA.", hub.fs(19), Art.CREAM)
        var cta := Art.Cta.new("CONHECER CLUB FRAIHA", "green", 62 * maxf(hub.k, 0.85), int(21 * maxf(hub.k, 0.85)))
        cta.name = "MyClubLocked"
        cta.pressed.connect(func(): hub.show_page("club"))
        hv.add_child(cta)
        return
    var list: Array = entries(hub)
    if list.is_empty():
        Art.label(hv, "Ainda não há partidas analisadas. Ao fim de uma partida, toque em ANALISAR: seus números aparecem aqui.", hub.fs(19), Art.CREAM)
    else:
        Art.label(hv, "%d partidas analisadas · análises ilimitadas no Club." % list.size(), hub.fs(18), Art.CREAM)
    weekly(hub, parent)
    _stats(hub, parent, list)
    _challenges(hub, parent, list)
    _training(hub, parent, list)
    _history(hub, parent, list)
    parent.add_child(hub.fair_play_note())

static func _pct(v: float) -> String:
    return "%d%%" % int(round(v))

## RELATÓRIO SEMANAL (dados reais). Também usado na página do Club quando o membro está ativo.
static func weekly(hub, parent: VBoxContainer):
    var v: VBoxContainer = hub.section(parent, "SUA SEMANA", "scroll", "parchment")
    v.get_parent().name = "WeeklyReport"
    var w: Dictionary = Insights.weekly(entries(hub), now())
    var d := Time.get_datetime_dict_from_unix_time(int(w.start))
    v.add_child(Art.Stamp.new("SEMANA DE %02d/%02d · DADOS REAIS" % [d.day, d.month], "ok", 13))
    var tight: bool = hub.narrow or hub.view.x < 1100.0
    var layout: BoxContainer = VBoxContainer.new() if tight else HBoxContainer.new()
    layout.add_theme_constant_override("separation", 26)
    v.add_child(layout)
    var stats := GridContainer.new()
    stats.name = "WeeklyNumbers"
    stats.columns = 3
    stats.add_theme_constant_override("h_separation", 14 if hub.narrow else 26)
    stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    layout.add_child(stats)
    for pair in [[str(w.games), "partidas analisadas"], [str(w.wins), "vitórias"], [_pct(w.accuracy) if int(w.games) > 0 else "—", "precisão média"]]:
        var cell := VBoxContainer.new()
        cell.custom_minimum_size.x = 92 if hub.narrow else 130
        stats.add_child(cell)
        var n := Art.label(cell, pair[0], hub.fs(44), Art.INK, Art.FONT_BOLD)
        n.autowrap_mode = TextServer.AUTOWRAP_OFF
        Art.label(cell, pair[1], hub.fs(16), Art.INK.lightened(0.2))
    var chart := WeekChart.new()
    chart.name = "WeeklyChart"
    chart.vals = w.days
    chart.custom_minimum_size = Vector2(0 if tight else 320, 120 * maxf(hub.k, 0.8))
    chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    layout.add_child(chart)
    var tips: BoxContainer = VBoxContainer.new() if tight else HBoxContainer.new()
    tips.add_theme_constant_override("separation", 16)
    v.add_child(tips)
    var focus := String(Insights.PHASE_NAMES.get(String(w.focus_phase), "")) if not String(w.focus_phase).is_empty() else "Jogue e analise partidas"
    var delta := ""
    if int(w.prev_games) > 0 and int(w.games) > 0:
        var dv: float = float(w.accuracy) - float(w.prev_accuracy)
        delta = ("+" if dv >= 0 else "") + "%d pts vs. semana passada" % int(round(dv))
    for pair in [["target", "Ponto para melhorar", focus], ["sword", "Treino recomendado", ("%d exercícios" % int(w.training)) if int(w.training) > 0 else "Sem erros para treinar"], ["chart", "Evolução", delta if not delta.is_empty() else "Compare na próxima semana"]]:
        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_theme_constant_override("separation", 10)
        tips.add_child(row)
        row.add_child(Art.Glyph.new(pair[0], 38, Art.INK))
        var col := VBoxContainer.new()
        col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(col)
        Art.label(col, pair[1], hub.fs(15), Art.INK.lightened(0.2))
        Art.label(col, pair[2], hub.fs(20), Art.INK, Art.FONT_BOLD)

static func _stats(hub, parent: VBoxContainer, list: Array):
    var v: VBoxContainer = hub.section(parent, "ESTATÍSTICAS AVANÇADAS", "chart", "club")
    v.get_parent().name = "AdvancedStats"
    var s: Dictionary = Insights.stats(list)
    if int(s.games) == 0:
        Art.label(v, "Analise partidas para ver sua precisão por modo, cor e fase do jogo.", hub.fs(17), Art.MUTED)
        return
    var g: GridContainer = hub.grid(v, 2 if hub.narrow else hub.columns_for(4))
    var trend: float = s.trend
    var cards := [
        ["PRECISÃO MÉDIA", _pct(s.accuracy), "melhor: " + _pct(s.best_accuracy)],
        ["RESULTADOS", "%dV %dE %dD" % [s.wins, s.draws, s.losses], "%d partidas analisadas" % s.games],
        ["TENDÊNCIA", ("+" if trend >= 0 else "") + "%d pts" % int(round(trend)), "últimas partidas vs. anteriores"],
        ["SEQUÊNCIA", "%d vitória%s" % [s.streak, "" if int(s.streak) == 1 else "s"], "seguidas (mais recentes)"],
        ["DE BRANCAS", _pct(s.by_color.w.accuracy) if int(s.by_color.w.games) > 0 else "—", "%d partidas" % s.by_color.w.games],
        ["DE PRETAS", _pct(s.by_color.b.accuracy) if int(s.by_color.b.games) > 0 else "—", "%d partidas" % s.by_color.b.games],
        ["ERROS GRAVES", "%.1f" % float(s.per_game.get("blunder", 0.0)), "por partida"],
        ["MELHORES LANCES", "%.1f" % float(s.per_game.get("best", 0.0)), "por partida"],
    ]
    for c in cards:
        var f := Art.Frame.new("dark", int(14 * hub.k))
        f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        g.add_child(f)
        var cv := VBoxContainer.new()
        f.add_child(cv)
        Art.label(cv, c[0], hub.fs(14), Art.MUTED, Art.FONT_SEMI)
        Art.label(cv, c[1], hub.fs(22 if hub.narrow else 30), Art.GOLD, Art.FONT_BOLD).autowrap_mode = TextServer.AUTOWRAP_OFF
        Art.label(cv, c[2], hub.fs(13), Art.CREAM)
    # por modo
    var modes := HFlowContainer.new()
    modes.add_theme_constant_override("h_separation", 10)
    modes.add_theme_constant_override("v_separation", 8)
    v.add_child(modes)
    for m in s.by_mode:
        var d: Dictionary = s.by_mode[m]
        modes.add_child(Art.Stamp.new("%s · %d · %s" % [String(Insights.MODE_NAMES.get(m, m)).to_upper(), int(d.games), _pct(d.accuracy)], "info", 13))
    # fases
    var ph := HBoxContainer.new()
    ph.add_theme_constant_override("separation", 18)
    v.add_child(ph)
    for p in ["opening", "middle", "end"]:
        var col := VBoxContainer.new()
        col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        ph.add_child(col)
        Art.label(col, String(Insights.PHASE_NAMES[p]).to_upper(), hub.fs(14), Art.MUTED, Art.FONT_SEMI)
        Art.label(col, "%d erros" % int(s.phases[p]), hub.fs(22), Color("f2a070") if p == s.weakest_phase else Art.CREAM, Art.FONT_BOLD)
    if not String(s.weakest_phase).is_empty():
        Art.label(v, "Ponto forte: %s  ·  Ponto fraco: %s" % [Insights.PHASE_NAMES[s.strongest_phase], Insights.PHASE_NAMES[s.weakest_phase]], hub.fs(17), Color("bfe8a8"))

static func _challenges(hub, parent: VBoxContainer, list: Array):
    var v: VBoxContainer = hub.section(parent, "DESAFIOS CLUB DA SEMANA", "trophy", "founder")
    v.get_parent().name = "ClubChallenges"
    Art.label(v, "Acompanhados automaticamente. Renovam toda segunda-feira.", hub.fs(16), Art.MUTED)
    var g: GridContainer = hub.grid(v, hub.columns_for(2))
    var done := 0
    var items: Array = Insights.challenges(list, now())
    for c in items:
        if c.done: done += 1
        var f := Art.Frame.new("reward" if c.done else "dark", int(14 * hub.k))
        f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        f.name = "Challenge_" + String(c.id)
        g.add_child(f)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        f.add_child(row)
        row.add_child(Art.Glyph.new("check" if c.done else "trophy", 40, Color("8fe08a") if c.done else Art.GOLD_MID, true))
        var cv := VBoxContainer.new()
        cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(cv)
        Art.label(cv, String(c.title), hub.fs(18), Art.GOLD, Art.FONT_BOLD)
        Art.label(cv, String(c.desc), hub.fs(14), Art.CREAM)
        var bar := ProgressBar.new()
        bar.max_value = float(c.goal)
        bar.value = float(c.progress)
        bar.show_percentage = false
        bar.custom_minimum_size.y = 10
        cv.add_child(bar)
        Art.label(cv, ("CONCLUÍDO" if c.done else "%d / %d" % [int(c.progress), int(c.goal)]), hub.fs(13), Color("8fe08a") if c.done else Art.MUTED)
    v.add_child(Art.Stamp.new("%d DE %d DESAFIOS CONCLUÍDOS" % [done, items.size()], "ok" if done == items.size() else "info", 14))

static func _training(hub, parent: VBoxContainer, list: Array):
    var v: VBoxContainer = hub.section(parent, "TREINOS", "target", "club")
    v.get_parent().name = "ClubTraining"
    var h = history(hub)
    var st = _stage(hub)
    var mine: Array = h.mistakes(10) if h != null else []
    var s: Dictionary = Insights.stats(list)
    var focus := String(s.weakest_phase)
    var focused: Array = h.mistakes(10, focus) if h != null and not focus.is_empty() else []
    var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    v.add_child(row)
    var a := _train_card(hub, row, "TREINE MEUS ERROS", "%d posições das suas últimas análises viram exercícios." % mine.size() if not mine.is_empty() else "Nenhum erro guardado ainda: analise partidas para treinar.", "TREINAR MEUS ERROS", mine)
    a.name = "TrainMistakes"
    var label := "Foco: %s — onde você mais erra." % Insights.PHASE_NAMES[focus] if not focus.is_empty() else "Aparece quando houver erros analisados."
    var b := _train_card(hub, row, "TREINO PERSONALIZADO", label, "TREINAR " + (String(Insights.PHASE_NAMES[focus]).to_upper() if not focus.is_empty() else "FOCO"), focused)
    b.name = "TrainFocused"
    if st == null: return

static func _train_card(hub, parent: Node, title: String, desc: String, cta_text: String, moves: Array) -> Control:
    var f := Art.Frame.new("dark", int(16 * hub.k))
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(f)
    var cv := VBoxContainer.new()
    cv.add_theme_constant_override("separation", 8)
    f.add_child(cv)
    Art.label(cv, title, hub.fs(20), Art.GOLD, Art.FONT_BOLD)
    Art.label(cv, desc, hub.fs(15), Art.CREAM)
    var b := Art.Cta.new(cta_text, "green" if not moves.is_empty() else "dark", 50 * maxf(hub.k, 0.85), int(16 * maxf(hub.k, 0.85)))
    b.name = "Go"
    b.disabled = moves.is_empty()
    b.pressed.connect(func():
        var st = _stage(hub)
        if st != null and st.has_method("open_training_moves"): st.open_training_moves(moves))
    cv.add_child(b)
    return f

static func _history(hub, parent: VBoxContainer, list: Array):
    var v: VBoxContainer = hub.section(parent, "HISTÓRICO DETALHADO", "hourglass", "dark")
    v.get_parent().name = "ClubHistory"
    if list.is_empty():
        Art.label(v, "Suas partidas analisadas aparecem aqui, da mais recente para a mais antiga.", hub.fs(16), Art.MUTED)
        return
    var h = history(hub)
    var shown := 0
    for e in list:
        if shown >= 20: break
        shown += 1
        var entry: Dictionary = e
        var f := Art.Frame.new("dark", int(12 * hub.k))
        f.name = "HistoryRow%d" % shown
        v.add_child(f)
        var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
        row.add_theme_constant_override("separation", 14)
        f.add_child(row)
        var info := VBoxContainer.new()
        info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(info)
        var d := Time.get_datetime_dict_from_unix_time(Insights.when(entry))
        var res: String = {"win": "VITÓRIA", "loss": "DERROTA", "draw": "EMPATE"}.get(String(entry.get("result", "")), "PARTIDA")
        var opp := String(entry.get("opponent", ""))
        Art.label(info, "%s  ·  %s%s" % [res, String(Insights.MODE_NAMES.get(String(entry.get("mode", "")), entry.get("mode", ""))), ("  ·  vs " + opp) if not opp.is_empty() else ""], hub.fs(17), Art.GOLD, Art.FONT_SEMI)
        var c: Dictionary = entry.get("counts", {})
        Art.label(info, "%02d/%02d/%d  ·  precisão %s  ·  %d erros graves · %d erros · %d imprecisões  ·  %s" % [d.day, d.month, d.year, _pct(float(entry.get("accuracy", 0.0))), int(c.get("blunder", 0)), int(c.get("mistake", 0)), int(c.get("inaccuracy", 0)), "Brancas" if String(entry.get("color", "")) == "w" else "Pretas"], hub.fs(14), Art.CREAM)
        var can: bool = h != null and h.has_report(entry)
        var b := Art.Cta.new("REVER ANÁLISE" if can else "SÓ RESUMO", "gold" if can else "dark", 44, 15)
        b.name = "Review"
        b.disabled = not can
        b.custom_minimum_size.x = 210
        b.pressed.connect(func():
            var st = _stage(hub)
            if st != null and st.has_method("open_history_report"): st.open_history_report(entry))
        row.add_child(b)
    if list.size() > shown:
        Art.label(v, "+%d partidas mais antigas (resumo guardado)." % (list.size() - shown), hub.fs(14), Art.MUTED)

## Barras por dia da semana (segunda a domingo).
class WeekChart extends Control:
    var vals: Array = [0, 0, 0, 0, 0, 0, 0]
    func _draw():
        var days := ["S", "T", "Q", "Q", "S", "S", "D"]
        var ink := Color("3a2a12")
        var base := size.y - 22.0
        var bw := size.x / (7 * 1.6)
        var top := 1
        for v in vals: top = maxi(top, int(v))
        var f := get_theme_default_font()
        draw_line(Vector2(0, base), Vector2(size.x, base), ink, 2.0)
        for i in 7:
            var x := i * bw * 1.6 + bw * 0.3
            var h: float = (base - 8.0) * float(vals[i]) / float(top)
            if h > 0.0:
                draw_rect(Rect2(x, base - h, bw, h), Color("2f6b2a"))
                draw_rect(Rect2(x, base - h, bw, h), ink, false, 1.5)
            draw_string(f, Vector2(x + bw * 0.25, size.y - 4), days[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
