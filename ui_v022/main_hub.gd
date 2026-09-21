extends CanvasLayer

signal play_local_requested
signal play_online_requested
signal bot_requested(level: String)
signal close_hub_requested

var root: Control
var main_panel: PanelContainer
var play_panel: PanelContainer
var bot_panel: PanelContainer
var info_panel: PanelContainer
var settings_panel: PanelContainer
var status_label: Label

func _ready():
    layer = 30
    _build()

func _style(bg: Color, border: Color, radius := 10) -> StyleBoxFlat:
    var s=StyleBoxFlat.new()
    s.bg_color=bg
    s.border_color=border
    s.set_border_width_all(2)
    s.set_corner_radius_all(radius)
    s.content_margin_left=28
    s.content_margin_right=28
    s.content_margin_top=22
    s.content_margin_bottom=22
    return s

func _button(parent: Control, title: String, callback: Callable, disabled := false) -> Button:
    var b=Button.new()
    b.text=title
    b.custom_minimum_size=Vector2(390,50)
    b.add_theme_font_size_override("font_size",17)
    var normal=_style(Color("#17291df0"),Color("#7f7048"),8)
    var hover=_style(Color("#25412cf8"),Color("#d2b56b"),8)
    var pressed=_style(Color("#0e1d14f8"),Color("#e4c878"),8)
    b.add_theme_stylebox_override("normal",normal)
    b.add_theme_stylebox_override("hover",hover)
    b.add_theme_stylebox_override("pressed",pressed)
    b.add_theme_color_override("font_color",Color("#e9dfc7"))
    b.add_theme_color_override("font_hover_color",Color("#f4d98b"))
    b.disabled=disabled
    parent.add_child(b)
    b.pressed.connect(callback)
    return b

func _panel(title: String) -> Array:
    var p=PanelContainer.new()
    p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    p.offset_left=-285; p.offset_right=285
    p.offset_top=-325; p.offset_bottom=325
    p.add_theme_stylebox_override("panel",_style(Color("#0d1811f2"),Color("#c5a45d"),14))
    root.add_child(p)
    var box=VBoxContainer.new()
    box.alignment=BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation",10)
    p.add_child(box)
    var h=Label.new()
    h.text=title
    h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    h.add_theme_font_size_override("font_size",34)
    h.add_theme_color_override("font_color",Color("#e7cd85"))
    box.add_child(h)
    return [p,box]

func _build():
    root=Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(root)
    var shade=ColorRect.new()
    shade.color=Color(0.008,0.022,0.012,0.52)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
    root.add_child(shade)

    var made=_panel("FRAIHA XADREZ")
    main_panel=made[0]
    var box:VBoxContainer=made[1]
    var subtitle=Label.new()
    subtitle.text="✦  DOMINE O TABULEIRO  •  CONQUISTE SEU ELO  ✦"
    subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size",14)
    subtitle.add_theme_color_override("font_color",Color("#c9b98d"))
    box.add_child(subtitle)
    var divider=HSeparator.new()
    divider.custom_minimum_size=Vector2(420,18)
    box.add_child(divider)
    _button(box,"JOGAR",func(): _show(play_panel))
    _button(box,"RANQUEADA  •  EM DESENVOLVIMENTO",func(): _message("Ranqueada será liberada com o sistema de ligas."),true)
    _button(box,"PERFIL",func(): _message("Perfil preparado para conta, elo, PL e histórico."))
    _button(box,"CONECTAR CONTA",func(): _message("Conexão de conta será ativada em uma próxima etapa."))
    _button(box,"CRIAR CONTA",func(): _message("Criação de conta será ativada em uma próxima etapa."))
    _button(box,"CONHEÇA O FRAIHA XADREZ",func(): _show(info_panel))
    _button(box,"CONFIGURAÇÕES",func(): _show(settings_panel))
    _button(box,"SAIR DO JOGO",func(): get_tree().quit())
    status_label=Label.new()
    status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    status_label.custom_minimum_size=Vector2(430,44)
    status_label.add_theme_color_override("font_color",Color("#c9b98d"))
    box.add_child(status_label)

    made=_panel("ESCOLHA COMO JOGAR")
    play_panel=made[0]; box=made[1]
    _button(box,"JOGAR ONLINE",func(): play_online_requested.emit())
    _button(box,"JOGAR LOCAL • DUAS PESSOAS",func(): play_local_requested.emit())
    _button(box,"JOGAR CONTRA BOT",func(): _show(bot_panel))
    _button(box,"VOLTAR",func(): _show(main_panel))

    made=_panel("JOGAR CONTRA BOT")
    bot_panel=made[0]; box=made[1]
    var note=Label.new()
    note.text="Escolha a dificuldade"
    note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(note)
    for level in ["FÁCIL","MÉDIO","DIFÍCIL","EXPERT"]:
        _button(box,level,func(l=level): bot_requested.emit(l))
    _button(box,"VOLTAR",func(): _show(play_panel))

    made=_panel("CONHEÇA O FRAIHA XADREZ")
    info_panel=made[0]; box=made[1]
    var info=Label.new()
    info.text="Uma experiência de xadrez em um mundo pixel-art vivo.\n\nJogue localmente, enfrente amigos online e, em breve, desafie bots e dispute ligas competitivas.\n\nLIGAS\nMadeira • Ferro • Bronze • Prata • Ouro • Platina\nEsmeralda • Diamante • Mestre • Grande Mestre • Challenger\n\nCada liga progride de 0 a 100 Pontos de Liga (PL)."
    info.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    info.custom_minimum_size=Vector2(440,260)
    box.add_child(info)
    _button(box,"VOLTAR",func(): _show(main_panel))

    made=_panel("CONFIGURAÇÕES")
    settings_panel=made[0]; box=made[1]
    _button(box,"ALTERNAR TELA CHEIA",_toggle_fullscreen)
    var ambient=HSlider.new()
    ambient.min_value=-50; ambient.max_value=0; ambient.value=-28
    ambient.custom_minimum_size=Vector2(360,34)
    box.add_child(ambient)
    var ambient_label=Label.new()
    ambient_label.text="Volume ambiente"
    ambient_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(ambient_label)
    ambient.value_changed.connect(_ambient_volume)
    _button(box,"VOLTAR",func(): _show(main_panel))

    _show(main_panel)

func _show(which: Control):
    for p in [main_panel,play_panel,bot_panel,info_panel,settings_panel]:
        if is_instance_valid(p): p.visible=(p==which)

func _message(text: String):
    status_label.text=text
    _show(main_panel)

func _toggle_fullscreen():
    var w=get_window()
    w.mode=Window.MODE_WINDOWED if w.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN

func _ambient_volume(db: float):
    var game=get_parent().get_node_or_null("World")
    if game and is_instance_valid(game.sound_ambient):
        game.sound_ambient.volume_db=db

func open_home():
    root.show()
    _show(main_panel)

func hide_hub():
    root.hide()
