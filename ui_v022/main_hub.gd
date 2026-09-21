extends CanvasLayer

signal play_local_requested
signal play_online_requested
signal bot_requested(level: String)

var root: Control
var pages := {}
var status_label: Label
var gold=Color("#d7ad58")
var cream=Color("#f1e6c9")
var deep=Color("#09150ff0")
var green=Color("#10271bf2")

func _ready():
    layer=30
    _build()

func style(bg:Color,border:Color,r:=8,w:=2)->StyleBoxFlat:
    var s=StyleBoxFlat.new()
    s.bg_color=bg; s.border_color=border
    s.set_border_width_all(w); s.set_corner_radius_all(r)
    s.content_margin_left=18; s.content_margin_right=18
    s.content_margin_top=14; s.content_margin_bottom=14
    return s

func label(text:String,size:int,color:=Color.WHITE)->Label:
    var l=Label.new(); l.text=text
    l.add_theme_font_size_override("font_size",size)
    l.add_theme_color_override("font_color",color)
    return l

func button(parent:Control,title:String,sub:String,cb:Callable,disabled:=false):
    var b=Button.new()
    b.text=title+("\n"+sub if not sub.is_empty() else "")
    b.custom_minimum_size=Vector2(430,62)
    b.add_theme_font_size_override("font_size",17)
    b.add_theme_color_override("font_color",cream)
    b.add_theme_color_override("font_hover_color",Color("#ffe3a0"))
    b.add_theme_stylebox_override("normal",style(Color("#10281df2"),Color("#947541"),7,1))
    b.add_theme_stylebox_override("hover",style(Color("#1c3b29fa"),gold,7,2))
    b.add_theme_stylebox_override("pressed",style(Color("#091a12fa"),Color("#f0cc79"),7,2))
    b.disabled=disabled; parent.add_child(b); b.pressed.connect(cb)

func card(parent:Control,min_size:Vector2)->VBoxContainer:
    var p=PanelContainer.new(); p.custom_minimum_size=min_size
    p.add_theme_stylebox_override("panel",style(deep,Color("#9d7d42"),8,1))
    parent.add_child(p)
    var v=VBoxContainer.new(); v.add_theme_constant_override("separation",8); p.add_child(v)
    return v

func _build():
    root=Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
    var shade=ColorRect.new(); shade.color=Color(0.005,0.018,0.01,0.34)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.mouse_filter=Control.MOUSE_FILTER_IGNORE; root.add_child(shade)

    var header=VBoxContainer.new()
    header.set_anchors_preset(Control.PRESET_CENTER_TOP)
    header.position=Vector2(-340,34); header.custom_minimum_size=Vector2(680,170)
    root.add_child(header)
    var crown=label("♛",42,gold); crown.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; header.add_child(crown)
    var title=label("FRAIHA",54,Color("#e4b65a")); title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; header.add_child(title)
    var chess=label("X A D R E Z",25,cream); chess.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; header.add_child(chess)
    var motto=label("ESTRATÉGIA PARA IR MAIS LONGE",13,Color("#d8c69c")); motto.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; header.add_child(motto)

    var left=VBoxContainer.new(); left.position=Vector2(32,190); left.custom_minimum_size=Vector2(280,0); root.add_child(left)
    var lv=card(left,Vector2(280,230))
    var lt=label("DISCIPLINA\n\nFOCO\n\nESTRATÉGIA\n\nEVOLUÇÃO",18,gold); lt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; lv.add_child(lt)
    var tip=card(left,Vector2(280,150)); tip.add_child(label("CADERNO DO ESTRATEGISTA",15,gold))
    tip.add_child(label("Planejamento\nTática\nEvolução",15,cream))

    var right=VBoxContainer.new(); right.set_anchors_preset(Control.PRESET_TOP_RIGHT); right.position=Vector2(-322,28); right.custom_minimum_size=Vector2(290,0); root.add_child(right)
    var profile=card(right,Vector2(290,150)); profile.add_child(label("♟  JOGADOR",14,gold)); profile.add_child(label("Gabriel",21,cream)); profile.add_child(label("Liga: Madeira  •  0 / 100 PL",13,Color("#cfc3a5"))); profile.add_child(label("Vitórias: 0  |  Derrotas: 0",13,Color("#cfc3a5")))
    var quote=card(right,Vector2(290,110)); var q=label("“O xadrez é a ginástica\nda inteligência.”\n— Blaise Pascal",13,cream); q.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; quote.add_child(q)

    var center=VBoxContainer.new(); center.set_anchors_preset(Control.PRESET_CENTER); center.position=Vector2(-235,-180); center.custom_minimum_size=Vector2(470,570); root.add_child(center)
    var main=PanelContainer.new(); main.add_theme_stylebox_override("panel",style(Color("#07150ff0"),gold,10,2)); center.add_child(main)
    var menu=VBoxContainer.new(); menu.add_theme_constant_override("separation",9); main.add_child(menu)
    pages["main"]=menu
    button(menu,"♟   JOGAR LOCAL","Duas pessoas no mesmo computador",func(): play_local_requested.emit())
    button(menu,"▣   JOGAR CONTRA O BOT","Treine e evolua seu jogo",func(): _show_page("bot"))
    button(menu,"◎   JOGAR ONLINE","Crie ou entre em uma sala",func(): play_online_requested.emit())
    button(menu,"▥   LIGAS E RANKING","Acompanhe seu progresso",func(): _message("Sistema competitivo em desenvolvimento."))
    button(menu,"⚙   CONFIGURAÇÕES","Áudio, vídeo e preferências",func(): _show_page("settings"))
    button(menu,"▣   CONHEÇA O FRAIHA","O mundo por trás do tabuleiro",func(): _show_page("about"))
    button(menu,"□   SAIR","Até a próxima partida!",func(): get_tree().quit())
    status_label=label("",12,Color("#d7c596")); status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; menu.add_child(status_label)

    var bot=_new_page(center,"ESCOLHA SEU ADVERSÁRIO")
    pages["bot"]=bot
    for level in ["FÁCIL","MÉDIO","DIFÍCIL","EXPERT"]: button(bot,level,"",func(l=level): bot_requested.emit(l))
    button(bot,"← VOLTAR","",func(): _show_page("main"))

    var settings=_new_page(center,"CONFIGURAÇÕES")
    pages["settings"]=settings
    button(settings,"TELA CHEIA","Alternar modo de exibição",_toggle_fullscreen)
    var vol=HSlider.new(); vol.min_value=-50; vol.max_value=0; vol.value=-28; vol.custom_minimum_size=Vector2(400,36); settings.add_child(vol); vol.value_changed.connect(_ambient_volume)
    var vl=label("VOLUME DO AMBIENTE",12,cream); vl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; settings.add_child(vl)
    button(settings,"← VOLTAR","",func(): _show_page("main"))

    var about=_new_page(center,"FRAIHA XADREZ")
    pages["about"]=about
    var tx=label("Um xadrez ambientado em um mundo pixel-art vivo.\n\nJogue localmente, enfrente amigos online e evolua pelas ligas do FRAIHA.\n\nMADEIRA • FERRO • BRONZE • PRATA • OURO\nPLATINA • ESMERALDA • DIAMANTE • MESTRE\nGRANDE MESTRE • CHALLENGER",15,cream)
    tx.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; tx.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; tx.custom_minimum_size=Vector2(420,260); about.add_child(tx)
    button(about,"← VOLTAR","",func(): _show_page("main"))

    var footer=PanelContainer.new(); footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); footer.offset_top=-64; footer.add_theme_stylebox_override("panel",style(Color("#07100ce8"),Color("#6e5832"),0,1)); root.add_child(footer)
    var fh=HBoxContainer.new(); footer.add_child(fh)
    var brand=label("♛  FRAIHA XADREZ  •  V0.22",14,cream); brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL; fh.add_child(brand)
    fh.add_child(label("MARINGÁ • PR • BRASIL",13,Color("#c9b98d")))
    _show_page("main")

func _new_page(parent:Control,title:String)->VBoxContainer:
    var p=PanelContainer.new(); p.visible=false; p.add_theme_stylebox_override("panel",style(Color("#07150ff5"),gold,10,2)); parent.add_child(p)
    var v=VBoxContainer.new(); v.add_theme_constant_override("separation",10); p.add_child(v)
    var h=label(title,25,gold); h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; v.add_child(h)
    return v

func _show_page(name:String):
    for k in pages: pages[k].get_parent().visible=(k==name)

func _message(t:String):
    status_label.text=t; _show_page("main")

func _toggle_fullscreen():
    var w=get_window(); w.mode=Window.MODE_WINDOWED if w.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN

func _ambient_volume(db:float):
    var game=get_parent().get_node_or_null("World")
    if game and is_instance_valid(game.sound_ambient): game.sound_ambient.volume_db=db

func open_home():
    root.show(); _show_page("main")

func hide_hub():
    root.hide()
