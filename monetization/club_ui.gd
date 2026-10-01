extends RefCounted
## CLUB FRAIHA — página da assinatura mensal (treinamento + análise + evolução).
## Estado exibido vem SOMENTE de dev_mock_club / dev_mock_founder_club_trial (simulação).
## Club NÃO inclui grupo de WhatsApp nesta fase. Nada aqui dá vantagem no Ranked.
const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")

const CONCEPT := "O Club FRAIHA transforma suas partidas em aprendizado.\n\nAnalise seu jogo, descubra seus erros recorrentes, acompanhe sua evolução e receba treinos direcionados aos pontos que mais precisam melhorar."

## [ícone, título, descrição, selo]
const BENEFITS := [
    ["magnifier", "ANÁLISE AVANÇADA DE PARTIDAS", "Erros, imprecisões, melhores jogadas, oportunidades perdidas e momentos críticos.", "EM DESENVOLVIMENTO"],
    ["target", "TREINE MEUS ERROS", "Posições problemáticas das suas partidas viram exercícios personalizados.", "EM DESENVOLVIMENTO"],
    ["sword", "TREINO PERSONALIZADO", "Sugestões conforme suas dificuldades: tática, abertura, meio-jogo e finais.", "EM DESENVOLVIMENTO"],
    ["chart", "ESTATÍSTICAS AVANÇADAS", "Evolução por período, ritmo e cor; sequências, precisão, pontos fortes e fracos.", "EM DESENVOLVIMENTO"],
    ["scroll", "RELATÓRIO SEMANAL", "Um resumo da sua semana com o ponto a melhorar e o treino recomendado.", "EM DESENVOLVIMENTO"],
    ["hourglass", "HISTÓRICO DETALHADO", "Todas as suas partidas organizadas para rever quando quiser.", "EM DESENVOLVIMENTO"],
    ["trophy", "DESAFIOS CLUB", "Desafios periódicos exclusivos para membros.", "EM BREVE"],
    ["gem", "COSMÉTICOS CLUB", "Itens visuais exclusivos — sem efeito no jogo.", "EM BREVE"],
    ["seal", "SELO CLUB", "Identificação de membro do Club.", "EM BREVE"],
    ["brush", "PERSONALIZAÇÃO PREMIUM", "Mais opções para deixar o FRAIHA com a sua cara.", "EM BREVE"],
    ["star", "ACESSO ANTECIPADO", "Experimente novidades antes do lançamento geral.", "EM BREVE"],
    ["tag", "DESCONTO FUTURO NA LOJA", "Condições especiais para membros na futura loja.", "EM BREVE"],
]

static func active_view(hub) -> String:
    if hub.state.club_subscription_view(): return "subscription"
    if hub.state.founder_trial_view(): return "trial"
    return ""

static func build(hub, parent: VBoxContainer):
    var active := active_view(hub)
    _hero(hub, parent, active)
    var c: VBoxContainer = hub.section(parent, "JOGUE. ENTENDA. EVOLUA.", "book", "club")
    Art.label(c, CONCEPT, hub.fs(19), Art.CREAM)
    _weekly_report(hub, parent)
    var b: VBoxContainer = hub.section(parent, "BENEFÍCIOS DO CLUB", "star", "club")
    var g: GridContainer = hub.grid(b, hub.columns_for(3))
    for item in BENEFITS:
        var tag: String = item[3]
        var tone := "soon"
        if not active.is_empty() and tag == "EM BREVE":
            tag = "INCLUSO · EM BREVE"
        hub.benefit_card(g, item[0], item[1], item[2], tag, tone, "dark")
    b.add_child(hub.fair_play_note())
    _yearly(hub, parent)

static func _hero(hub, parent: VBoxContainer, active: String):
    var f := Art.Frame.new("club", int(30 * hub.k))
    f.name = "ClubHero"
    f.glow = not active.is_empty()
    parent.add_child(f)
    var layout: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    layout.add_theme_constant_override("separation", int(28 * hub.k))
    f.add_child(layout)
    var emblem := VBoxContainer.new()
    emblem.alignment = BoxContainer.ALIGNMENT_CENTER
    emblem.add_theme_constant_override("separation", 4)
    layout.add_child(emblem)
    var book := Art.Glyph.new("book", (170 if not hub.narrow else 110) * hub.k, Art.GOLD, true)
    book.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    emblem.add_child(book)
    var icons := HBoxContainer.new()
    icons.alignment = BoxContainer.ALIGNMENT_CENTER
    icons.add_theme_constant_override("separation", 10)
    emblem.add_child(icons)
    for k in ["chart", "pawn", "scroll"]: icons.add_child(Art.Glyph.new(k, 40 * hub.k, Art.GOLD_MID))
    var v := VBoxContainer.new()
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    v.add_theme_constant_override("separation", int(10 * hub.k))
    layout.add_child(v)
    var chips := HFlowContainer.new()
    chips.add_theme_constant_override("h_separation", 8)
    chips.add_theme_constant_override("v_separation", 6)
    v.add_child(chips)
    chips.add_child(Art.Stamp.new("ASSINATURA MENSAL", "info", 15))
    chips.add_child(Art.Stamp.new("CANCELE QUANDO QUISER", "info", 15))
    var t := Art.label(v, "CLUB FRAIHA", hub.fs(48), Art.GOLD, Art.FONT_BOLD)
    t.add_theme_constant_override("outline_size", 8)
    t.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.05, 0.95))
    Art.label(v, "JOGUE.  ENTENDA.  EVOLUA.", hub.fs(26), Color("bfe8a8"), Art.FONT_BOLD)
    if active == "subscription":
        v.add_child(hub.status_badge("CLUB FRAIHA ATIVO"))
        var on := Art.label(v, "Sua assinatura de teste está ativa. Os recursos do Club aparecem aqui conforme forem lançados.", hub.fs(19), Art.CREAM)
        on.name = "ClubActiveText"
        Art.label(v, "Estado de desenvolvimento (simulação): nenhuma cobrança real.", hub.fs(15), Color("f2a070"))
        if Catalog.dev_tools_enabled():
            var off := Art.Cta.new("DESATIVAR CLUB", "ember", 56, 18)
            off.name = "DeactivateClub"
            off.pressed.connect(func():
                hub.state.mock_deactivate_club()
                hub._rebuild())
            v.add_child(off)
        if hub.state.founder_trial_view():
            Art.label(v, "Você também tem %d dias de Club como benefício Fundador (simulação)." % Catalog.FOUNDER_CLUB_DAYS, hub.fs(15), Art.MUTED)
        return
    if active == "trial":
        v.add_child(hub.status_badge("%d DIAS DE CLUB · BENEFÍCIO FUNDADOR · SIMULAÇÃO" % Catalog.FOUNDER_CLUB_DAYS))
        Art.label(v, "Benefício simulado do Pacote Fundador. Não é uma assinatura.", hub.fs(16), Color("f2a070"))
    v.add_child(hub.price_block("club_monthly", true))
    var cta := Art.Cta.new("ASSINAR CLUB FRAIHA", "green", 70 * maxf(hub.k, 0.85), int(25 * maxf(hub.k, 0.85)))
    cta.name = "SubscribeClub"
    cta.icon_kind = "book"
    cta.shimmer = true
    cta.pressed.connect(func(): hub.open_payment("club_monthly"))
    v.add_child(cta)

## Exemplo visual do relatório semanal (pergaminho com selo EXEMPLO).
static func _weekly_report(hub, parent: VBoxContainer):
    var v: VBoxContainer = hub.section(parent, "SUA SEMANA", "scroll", "parchment")
    v.get_parent().name = "WeeklyReport"
    v.add_child(Art.Stamp.new("EXEMPLO · DADOS FICTÍCIOS", "test", 13))
    var layout: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    layout.add_theme_constant_override("separation", 26)
    v.add_child(layout)
    var stats := GridContainer.new()
    stats.columns = 3
    stats.add_theme_constant_override("h_separation", 14 if hub.narrow else 26)
    stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    layout.add_child(stats)
    for pair in [["12", "partidas"], ["7", "vitórias"], ["3", "erros recorrentes"]]:
        var cell := VBoxContainer.new()
        cell.custom_minimum_size.x = 92 if hub.narrow else 130
        stats.add_child(cell)
        var n := Art.label(cell, pair[0], hub.fs(44), Art.INK, Art.FONT_BOLD)
        n.autowrap_mode = TextServer.AUTOWRAP_OFF
        Art.label(cell, pair[1], hub.fs(16), Art.INK.lightened(0.2))
    var chart := ReportChart.new()
    chart.custom_minimum_size = Vector2(0 if hub.narrow else 320, 120 * maxf(hub.k, 0.8))
    chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    layout.add_child(chart)
    var tips: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    tips.add_theme_constant_override("separation", 16)
    v.add_child(tips)
    for pair in [["target", "Ponto para melhorar", "Finais de torre"], ["sword", "Treino recomendado", "8 exercícios"]]:
        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_theme_constant_override("separation", 10)
        tips.add_child(row)
        row.add_child(Art.Glyph.new(pair[0], 38, Art.INK))
        var col := VBoxContainer.new()
        col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(col)
        Art.label(col, pair[1], hub.fs(15), Art.INK.lightened(0.2))
        Art.label(col, pair[2], hub.fs(22), Art.INK, Art.FONT_BOLD)

static func _yearly(hub, parent: VBoxContainer):
    var f := Art.Frame.new("dark", int(20 * hub.k))
    f.name = "YearlyPlan"
    parent.add_child(f)
    var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    f.add_child(row)
    row.add_child(Art.Glyph.new("calendar", 54, Art.GOLD_MID, true))
    var v := VBoxContainer.new()
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(v)
    Art.label(v, "PLANO ANUAL", hub.fs(24), Art.GOLD, Art.FONT_BOLD)
    Art.label(v, "%s / ANO · preço planejado" % Catalog.planned_price("club_yearly"), hub.fs(18), Art.CREAM)
    var s := Art.Stamp.new("EM BREVE · AINDA NÃO DISPONÍVEL", "soon", 13)
    s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(s)

## Gráfico de barras "de pergaminho" para o exemplo do relatório.
class ReportChart extends Control:
    func _draw():
        var vals := [2, 1, 3, 0, 2, 3, 1]
        var days := ["S", "T", "Q", "Q", "S", "S", "D"]
        var ink := Color("3a2a12")
        var base := size.y - 22.0
        var bw := size.x / (vals.size() * 1.6)
        var f := get_theme_default_font()
        draw_line(Vector2(0, base), Vector2(size.x, base), ink, 2.0)
        for i in vals.size():
            var x := i * bw * 1.6 + bw * 0.3
            var h: float = (base - 8.0) * vals[i] / 3.0
            draw_rect(Rect2(x, base - h, bw, h), Color("2f6b2a"))
            draw_rect(Rect2(x, base - h, bw, h), ink, false, 1.5)
            draw_string(f, Vector2(x + bw * 0.25, size.y - 4), days[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
