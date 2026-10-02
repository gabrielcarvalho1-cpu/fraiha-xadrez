extends RefCounted
## PACOTE FUNDADOR FRAIHA — página do produto (compra única, edição limitada).
## Estado exibido vem SOMENTE de dev_mock_founder (simulação). Nenhum benefício é competitivo.
const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")

const CONCEPT := "O Pacote Fundador é para os primeiros jogadores que acreditam no FRAIHA e querem fazer parte do começo desta história.\n\nAlém de benefícios exclusivos e permanentes, o Fundador apoia diretamente o desenvolvimento do jogo, a manutenção dos servidores e a criação de novos recursos.\n\nSeu status de Fundador fica ligado à sua conta como sinal de que você esteve aqui desde o início."

const WHY := [
    ["hammer", "Ajuda no desenvolvimento do FRAIHA"],
    ["server", "Ajuda a manter servidores e infraestrutura"],
    ["star", "Apoia a criação de novos recursos"],
    ["people", "Participa da primeira geração da comunidade"],
    ["shield", "Recebe uma identidade permanente"],
    ["chat", "Fica mais perto do desenvolvimento"],
    ["crown", "Tem acesso a benefícios exclusivos de lançamento"],
]

## [ícone, título, descrição, estado depois de ativar (TESTE)]
const BENEFITS := [
    ["seal", "SELO FUNDADOR PERMANENTE", "Emblema ao lado do seu nome, no perfil e na tela inicial.", "now"],
    ["crown", "AVATAR FUNDADOR EXCLUSIVO", "Rei e Rainha dourados — só para Fundadores.", "now"],
    ["scroll", "TÍTULO EXCLUSIVO", "“Fundador do Reino”.", "now"],
    ["frame", "MOLDURA DE PERFIL EXCLUSIVA", "Visual especial reservado aos Fundadores.", "now"],
    ["pawn", "CONJUNTO DE PEÇAS FUNDADOR", "Conjunto exclusivo, fora da progressão do Ranked.", "soon"],
    ["castle", "UNIVERSO FUNDADOR", "Cenário e tabuleiro exclusivos, fora das ligas.", "soon"],
    ["chat", "COMUNIDADE DOS FUNDADORES", "Grupo exclusivo dos Fundadores no WhatsApp.", "now"],
    ["hourglass", "ACESSO ANTECIPADO", "Teste algumas novidades antes do lançamento geral.", "soon"],
    ["megaphone", "DESTAQUE SOCIAL", "Futuramente no perfil, na lista de Amigos, no chat e em outras áreas sociais.", "soon"],
    ["calendar", "30 DIAS DE CLUB FRAIHA", "Um mês de Club FRAIHA incluso no Pacote Fundador.", "trial"],
]

static func build(hub, parent: VBoxContainer):
    var owned: bool = hub.state.founder_view()
    _hero(hub, parent, owned)
    if owned: _reward(hub, parent)
    # O reino começa aqui (conceito)
    var c: VBoxContainer = hub.section(parent, "O REINO COMEÇA AQUI", "crown", "founder")
    Art.label(c, CONCEPT, hub.fs(19), Art.CREAM)
    # Por que ser Fundador?
    var w: VBoxContainer = hub.section(parent, "POR QUE SER FUNDADOR?", "shield")
    var g: GridContainer = hub.grid(w, hub.columns_for(2))
    for item in WHY:
        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_theme_constant_override("separation", 12)
        g.add_child(row)
        row.add_child(Art.Glyph.new(item[0], 40 * maxf(hub.k, 0.8), Art.GOLD, true))
        var l := Art.label(row, item[1], hub.fs(18), Art.CREAM)
        l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # Benefícios
    var b: VBoxContainer = hub.section(parent, "BENEFÍCIOS DO FUNDADOR", "star", "founder")
    var bg: GridContainer = hub.grid(b, hub.columns_for(3))
    for item in BENEFITS:
        var tag := ""
        var tone := "soon"
        if owned:
            match item[3]:
                "now": tag = "LIBERADO · TESTE"; tone = "ok"
                "trial": tag = "%d DIAS DE CLUB · BENEFÍCIO FUNDADOR · SIMULAÇÃO" % Catalog.FOUNDER_CLUB_DAYS; tone = "ok"
                _: tag = "EM BREVE"
        elif item[3] == "trial":
            tag = "BENEFÍCIO FUTURO"
        hub.benefit_card(bg, item[0], item[1], item[2], tag, tone, "dark")
    b.add_child(hub.fair_play_note())
    if not owned:
        var again: Button = Art.Cta.new("TORNAR-SE FUNDADOR", "gold", 68 * maxf(hub.k, 0.85), int(24 * maxf(hub.k, 0.85)))
        again.name = "BecomeFounderBottom"
        again.shimmer = true
        again.pressed.connect(func(): hub.open_payment("founder"))
        parent.add_child(again)

static func _hero(hub, parent: VBoxContainer, owned: bool):
    var f := Art.Frame.new("founder", int(30 * hub.k))
    f.name = "FounderHero"
    f.glow = true
    parent.add_child(f)
    var layout: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    layout.add_theme_constant_override("separation", int(28 * hub.k))
    f.add_child(layout)
    # Arte oficial do Pacote Fundador (o mesmo emblema do Selo Fundador do perfil)
    var emblem := TextureRect.new()
    emblem.name = "FounderEmblem"
    emblem.texture = preload("res://monetization/art/founder_badge.png")
    var es: float = (300.0 if not hub.narrow else 190.0) * hub.k
    emblem.custom_minimum_size = Vector2(es, es)
    emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    layout.add_child(emblem)
    var v := VBoxContainer.new()
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    v.add_theme_constant_override("separation", int(10 * hub.k))
    layout.add_child(v)
    var chips := HFlowContainer.new()
    chips.add_theme_constant_override("h_separation", 8)
    chips.add_theme_constant_override("v_separation", 6)
    v.add_child(chips)
    chips.add_child(Art.Stamp.new("EDIÇÃO DE LANÇAMENTO", "new", 14))
    chips.add_child(Art.Stamp.new("EDIÇÃO LIMITADA", "new", 14))
    var t := Art.label(v, "PACOTE FUNDADOR FRAIHA", hub.fs(46), Art.GOLD, Art.FONT_BOLD)
    t.add_theme_constant_override("outline_size", 8)
    t.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.0, 0.95))
    var lim := Art.label(v, "Primeiros %d Fundadores do FRAIHA" % Catalog.FOUNDER_LIMIT, hub.fs(20), Color("ffe6a0"), Art.FONT_SEMI)
    lim.name = "FounderLimit"
    if owned:
        v.add_child(hub.status_badge("FUNDADOR DO REINO"))
        var big := Art.label(v, "FUNDADOR FRAIHA", hub.fs(34), Color("fff1c0"), Art.FONT_BOLD)
        big.name = "FounderOwnedTitle"
        Art.label(v, "Você faz parte de quem esteve aqui desde o começo.", hub.fs(22), Art.CREAM)
        Art.label(v, "Estado de desenvolvimento (simulação): nenhuma compra real foi feita.", hub.fs(15), Color("f2a070"))
    else:
        v.add_child(hub.price_block("founder", false))
        var pay := HFlowContainer.new()
        pay.add_theme_constant_override("h_separation", 8)
        pay.add_theme_constant_override("v_separation", 6)
        v.add_child(pay)
        pay.add_child(Art.Stamp.new("PAGAMENTO ÚNICO", "info", 15))
        pay.add_child(Art.Stamp.new("SEM MENSALIDADE", "info", 15))
        var cta := Art.Cta.new("TORNAR-SE FUNDADOR", "gold", 70 * maxf(hub.k, 0.85), int(25 * maxf(hub.k, 0.85)))
        cta.name = "BecomeFounder"
        cta.icon_kind = "crown"
        cta.shimmer = true
        cta.pressed.connect(func(): hub.open_payment("founder"))
        v.add_child(cta)

static func _reward(hub, parent: VBoxContainer):
    var f := Art.Frame.new("reward", int(26 * hub.k))
    f.name = "FounderReward"
    f.glow = true
    parent.add_child(f)
    var layout: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    layout.add_theme_constant_override("separation", 22)
    f.add_child(layout)
    var g := Art.Glyph.new("chat", 96 * maxf(hub.k, 0.8), Color("ffd76a"), true)
    g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    layout.add_child(g)
    var v := VBoxContainer.new()
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    v.add_theme_constant_override("separation", 8)
    layout.add_child(v)
    v.add_child(Art.Stamp.new("RECOMPENSA DESBLOQUEADA", "new", 15))
    Art.label(v, "COMUNIDADE DOS FUNDADORES", hub.fs(30), Art.GOLD, Art.FONT_BOLD)
    Art.label(v, "Seu acesso à comunidade exclusiva dos Fundadores foi liberado.", hub.fs(20), Art.CREAM)
    Art.label(v, "Bastidores, novidades antecipadas, sugestões e conversas sobre o futuro do jogo.", hub.fs(16), Art.MUTED)
    var b := Art.Cta.new("ENTRAR NO GRUPO DOS FUNDADORES", "gold", 64 * maxf(hub.k, 0.85), int(21 * maxf(hub.k, 0.85)))
    b.name = "JoinFounderGroup"
    b.icon_kind = "chat"
    b.pressed.connect(hub.open_founder_group)
    v.add_child(b)
