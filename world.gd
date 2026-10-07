extends Node2D

# V0.17 CLEAN: camada visual simplificada; regras preservadas.
var tile_light_tex = preload("res://visual_v014/tile_light.png")
var tile_dark_tex = preload("res://visual_v014/tile_dark.png")

const TILE := 75
const BOARD := TILE * 8
const ORIGIN := Vector2(210,186)
var arena_bg: Texture2D
var piece_textures := {}
var visual_theme := "wood"
var board_palette := [Color("a8aca5"),Color("364955")]
## R31 · LABORATÓRIO (acesso antecipado Fundador/Club): letras e números nas casas da borda.
var show_coordinates := false

func board_flipped() -> bool:
    if bot != null: return bot.human_color == "b"
    if online != null: return online.color == "b"
    return false

func display_cell(cell: Vector2i) -> Vector2i:
    return Vector2i(7,7)-cell if board_flipped() else cell

func square_center(cell: Vector2i) -> Vector2:
    return ORIGIN+(Vector2(display_cell(cell))+Vector2(0.5,0.5))*TILE

func cell_at(point: Vector2) -> Vector2i:
    var local = point-ORIGIN
    if local.x < 0 or local.y < 0 or local.x >= BOARD or local.y >= BOARD:
        return Vector2i(-1,-1)
    return display_cell(Vector2i(floori(local.x/TILE),floori(local.y/TILE)))

var pieces := {}
var selected := Vector2i(-1,-1)
var legal_moves: Array[Vector2i] = []
var turn := "w"
var last_from := Vector2i(-1,-1)
var last_to := Vector2i(-1,-1)
var captured_white: Array[String] = []
var captured_black: Array[String] = []
var status := "BRANCAS JOGAM"
var move_count := 0
var particles: Array = []
var flash := 0.0
var flash_pos := Vector2.ZERO
var promotion_pending := false
var promotion_cell := Vector2i(-1,-1)
var promotion_color := "w"
var game_over := false
var server_mode := false
var online = null
var bot = null
var sound_move: AudioStreamPlayer
var sound_capture: AudioStreamPlayer
var sound_promotion: AudioStreamPlayer
var sound_ambient: AudioStreamPlayer
var sound_water: AudioStreamPlayer
var anim_time := 0.0
var game_started := false
var start_button := Rect2(420, 918, 184, 42)
var restart_button := Rect2(852, 18, 112, 34)
var gear_button := Rect2(974, 18, 34, 34)
var drag_origin := Vector2i(-1, -1)
var drag_start := Vector2.ZERO
var drag_position := Vector2.ZERO
var dragging := false
var settings_open := false
var mobile_presentation := false
# Pré-move (como no Chess.com): na vez do adversário, deixa um lance marcado; ele é
# jogado sozinho assim que chegar a sua vez (se ainda for legal; senão é descartado).
var premove_enabled := true
var premove_from := Vector2i(-1,-1)
var premove_to := Vector2i(-1,-1)
var premove_selecting := false
var check_flash := 0.0
# ---------- Animação do lance + destaque de origem/destino (SÓ apresentação; regras intactas) ----------
# Antes o tabuleiro trocava o dicionário `pieces` de uma vez (peça "teletransportava") e o último lance
# tinha só um tom fraco fixo. Agora show_move() anima a(s) peça(s) que mudaram de casa a partir do
# tabuleiro ANTERIOR e do já aplicado (o resultado vem das regras: bot, servidor ou partida local).
const MOVE_ANIM := 0.55          # R38: adversário / bot / remoto (antes 0,32 — chegava "de repente")
const OWN_MOVE_ANIM := 0.32      # R38: lance do próprio jogador por clique (antes 0,18); arrastar não anima de novo
const MOVE_PER_SQUARE := 0.035   # R38: lances longos levam um pouco mais (até +0,25 s)
const MOVE_LIFT := 0.16          # R38: a peça sobe um pouco no meio do caminho (fração da casa)
const LAST_MOVE_HOLD := 1.6      # destaque forte do lance recebido
const LAST_MOVE_FADE := 0.6
const HL_FROM := Color(1.0, 0.70, 0.22)    # origem: dourado/âmbar suave
const HL_TO := Color(0.80, 0.95, 0.30)     # destino: dourado-esverdeado, mais forte
var move_anim := []              # [{code, from: Vector2, to: Vector2, final: String}]
var move_fades := []             # [{code, at: Vector2}] peças capturadas sumindo
var move_hidden := {}            # casas cujo conteúdo final só aparece no fim da animação
var move_anim_t := 1.0
var move_anim_len := MOVE_ANIM
var last_move_emph := false      # lance do adversário/remoto: destaque forte que esmaece
var last_move_age := 99.0
var _drag_submit := []           # [from, to] do lance que o jogador acabou de soltar arrastando
const PREMOVE_TINT := Color(0.22,0.52,0.95,0.50)
# Desktop: engrenagem e reiniciar viram botões do HUD (stage); o tabuleiro só desenha o painel de opções.
var external_hud := false
var hide_status := false        # R49 · pele do tabuleiro Ranked: sem a plaquinha de status embaixo (o relógio da vez acende)
var presentation_rect := Rect2(0, 0, 1024, 1024)
var settings_panel := Rect2(776, 60, 232, 136)
var fullscreen_button := Rect2(788, 134, 208, 38)

func _ready():
    if server_mode:
        _new_game()
        return
    # Pixel art limpa: nearest evita halos coloridos nas bordas transparentes dos sprites.
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    arena_bg = null
    var environment = preload("res://presentation_v019/environment.tscn").instantiate()
    add_child(environment)
    move_child(environment, 0)
    for code in ["wP","wR","wN","wB","wQ","wK","bP","bR","bN","bB","bQ","bK"]:
        piece_textures[code] = load("res://visual_v018/pieces/" + code + ".tres")
    # Environmental audio is disabled. Music and chess cues are owned by GameAudio.
    _new_game()
    set_process(true)

func _new_game():
    clear_premove()
    if bot != null:
        bot.restart()
        return
    if online != null:
        online.send_action("restart")
        return
    pieces.clear()
    var back = ["R","N","B","Q","K","B","N","R"]
    for x in range(8):
        pieces[Vector2i(x,0)] = "b"+back[x]
        pieces[Vector2i(x,1)] = "bP"
        pieces[Vector2i(x,6)] = "wP"
        pieces[Vector2i(x,7)] = "w"+back[x]
    selected = Vector2i(-1,-1)
    legal_moves.clear()
    captured_white.clear()
    captured_black.clear()
    turn = "w"
    clear_last_move()
    move_count = 0
    status = "BRANCAS JOGAM"
    particles.clear()
    promotion_pending = false
    promotion_cell = Vector2i(-1,-1)
    game_over = false
    queue_redraw()

func _process(delta):
    if server_mode:
        return
    anim_time += delta
    var alive := []
    for p in particles:
        p["life"] -= delta
        p["pos"] += p["vel"] * delta
        p["vel"] *= 0.93
        if p["life"] > 0:
            alive.append(p)
    particles = alive
    flash = max(0.0, flash-delta*3.5)
    check_flash = max(0.0, check_flash-delta*1.6)
    if move_anim_t < 1.0:
        move_anim_t = minf(1.0, move_anim_t + delta / move_anim_len)
        if move_anim_t >= 1.0: _finish_move_anim()
    last_move_age += delta
    _premove_tick()
    # cenário vivo: redesenha continuamente para água, fogo e vegetação
    queue_redraw()

func set_visual_theme(theme_id: String):
    visual_theme = theme_id
    board_palette = preload("res://cosmetics/theme_catalog.gd").get_theme(theme_id).get("board_palette",[Color("a8aca5"),Color("364955")])
    var environment = get_node_or_null("ForestEnvironment")
    if environment != null: environment.visible = theme_id == "wood"
    queue_redraw()

func _inside(p:Vector2i)->bool:
    return p.x>=0 and p.x<8 and p.y>=0 and p.y<8

func _color_at(p:Vector2i)->String:
    return String(pieces[p]).substr(0,1) if pieces.has(p) else ""

func _ray(out:Array[Vector2i], fr:Vector2i, d:Vector2i):
    var p=fr+d
    var mine=_color_at(fr)
    while _inside(p):
        if not pieces.has(p):
            out.append(p)
        else:
            if _color_at(p)!=mine: out.append(p)
            break
        p+=d

func _pseudo_moves(fr:Vector2i)->Array[Vector2i]:
    var out:Array[Vector2i]=[]
    if not pieces.has(fr): return out
    var code:String=pieces[fr]
    var c=code.substr(0,1)
    var k=code.substr(1,1)
    if k=="P":
        var dy=-1 if c=="w" else 1
        var sy=6 if c=="w" else 1
        var one=fr+Vector2i(0,dy)
        if _inside(one) and not pieces.has(one):
            out.append(one)
            var two=fr+Vector2i(0,dy*2)
            if fr.y==sy and not pieces.has(two): out.append(two)
        for dx in [-1,1]:
            var q=fr+Vector2i(dx,dy)
            if _inside(q) and pieces.has(q) and _color_at(q)!=c: out.append(q)
    elif k=="N":
        for d in [Vector2i(1,2),Vector2i(2,1),Vector2i(2,-1),Vector2i(1,-2),Vector2i(-1,-2),Vector2i(-2,-1),Vector2i(-2,1),Vector2i(-1,2)]:
            var q=fr+d
            if _inside(q) and (not pieces.has(q) or _color_at(q)!=c): out.append(q)
    elif k=="B":
        for d in [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]: _ray(out,fr,d)
    elif k=="R":
        for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]: _ray(out,fr,d)
    elif k=="Q":
        for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]: _ray(out,fr,d)
    elif k=="K":
        for yy in range(-1,2):
            for xx in range(-1,2):
                if xx==0 and yy==0: continue
                var q=fr+Vector2i(xx,yy)
                if _inside(q) and (not pieces.has(q) or _color_at(q)!=c): out.append(q)
    return out


func _find_king(color:String)->Vector2i:
    for pos in pieces.keys():
        if String(pieces[pos]) == color+"K": return pos
    return Vector2i(-1,-1)

func _square_attacked(square:Vector2i, by_color:String)->bool:
    # Pawns attack diagonally even when the target square is empty.
    var pawn_dy = -1 if by_color=="w" else 1
    for dx in [-1,1]:
        var src=square-Vector2i(dx,pawn_dy)
        if _inside(src) and pieces.has(src) and String(pieces[src])==by_color+"P": return true
    for d in [Vector2i(1,2),Vector2i(2,1),Vector2i(2,-1),Vector2i(1,-2),Vector2i(-1,-2),Vector2i(-2,-1),Vector2i(-2,1),Vector2i(-1,2)]:
        var src=square-d
        if _inside(src) and pieces.has(src) and String(pieces[src])==by_color+"N": return true
    for yy in range(-1,2):
        for xx in range(-1,2):
            if xx==0 and yy==0: continue
            var src=square+Vector2i(xx,yy)
            if _inside(src) and pieces.has(src) and String(pieces[src])==by_color+"K": return true
    for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
        var q=square+d
        while _inside(q):
            if pieces.has(q):
                var code:String=pieces[q]
                if code.substr(0,1)==by_color and code.substr(1,1) in ["R","Q"]: return true
                break
            q+=d
    for d in [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
        var q=square+d
        while _inside(q):
            if pieces.has(q):
                var code:String=pieces[q]
                if code.substr(0,1)==by_color and code.substr(1,1) in ["B","Q"]: return true
                break
            q+=d
    return false

func _in_check(color:String)->bool:
    var king=_find_king(color)
    if king==Vector2i(-1,-1): return true
    return _square_attacked(king,"b" if color=="w" else "w")

func _moves(fr:Vector2i)->Array[Vector2i]:
    if bot != null: return bot.legal_from(fr)
    var legal:Array[Vector2i]=[]
    if not pieces.has(fr): return legal
    var color=_color_at(fr)
    for to in _pseudo_moves(fr):
        # Kings are never captured; checkmate ends the game instead.
        if pieces.has(to) and String(pieces[to]).substr(1,1)=="K": continue
        var moving:String=pieces[fr]
        var had_target=pieces.has(to)
        var target:String=pieces[to] if had_target else ""
        pieces.erase(fr)
        pieces[to]=moving
        var safe=not _in_check(color)
        pieces.erase(to)
        pieces[fr]=moving
        if had_target: pieces[to]=target
        if safe: legal.append(to)
    return legal

func _has_legal_move(color:String)->bool:
    for pos in pieces.keys():
        if _color_at(pos)==color and not _moves(pos).is_empty(): return true
    return false

func _update_game_state():
    var checked=_in_check(turn)
    var can_move=_has_legal_move(turn)
    if not can_move:
        game_over=true
        if checked:
            status="XEQUE-MATE! BRANCAS VENCEM" if turn=="b" else "XEQUE-MATE! PRETAS VENCEM"
        else:
            status="EMPATE — AFOGAMENTO"
    elif checked:
        status="XEQUE! PRETAS JOGAM" if turn=="b" else "XEQUE! BRANCAS JOGAM"
    else:
        status="PRETAS JOGAM" if turn=="b" else "BRANCAS JOGAM"

func _spawn_capture(center:Vector2, victim:String):
    flash=1.0
    flash_pos=center
    var col=Color("#f2cf68") if victim.substr(0,1)=="w" else Color("#d64d45")
    for i in range(22):
        var a=float(i)/22.0*TAU
        var speed=70.0+float((i*37)%90)
        particles.append({"pos":center,"vel":Vector2(cos(a),sin(a))*speed,"life":0.45+float(i%5)*0.05,"col":col})

func _draw_promotion_overlay():
    if mobile_presentation: return
    if not promotion_pending: return
    if online != null and promotion_color != online.color: return
    var font=ThemeDB.fallback_font
    draw_rect(presentation_rect,Color(0,0,0,0.58))
    var box=Rect2(222,363,580,250)
    draw_rect(box,Color("#201813"))
    draw_rect(box.grow(-8),Color("#b88a4a"),false,4)
    draw_string(font,Vector2(286,413),"PROMOÇÃO DO PEÃO",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("#f0cf77"))
    draw_string(font,Vector2(286,446),"Escolha a nova peça",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("#e8ddc3"))
    var opts=["Q","R","B","N"]
    for i in range(4):
        var rr=Rect2(269+i*130,473,105,95)
        draw_rect(rr,Color("#4d6c3d") if i%2==0 else Color("#b89a61"))
        draw_rect(rr,Color("#f0cf77"),false,3)
        _piece(rr.get_center()+Vector2(0,3),promotion_color+opts[i])
        draw_string(font,Vector2(rr.position.x+43,595),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("#f0cf77"))

func _finish_promotion(kind:String):
    if bot != null:
        bot.promote(kind)
        return
    if online != null:
        online.send_action("promote", {"kind":kind})
        return
    if not promotion_pending: return
    pieces[promotion_cell]=promotion_color+kind
    promotion_pending=false
    promotion_cell=Vector2i(-1,-1)
    _update_game_state()
    queue_redraw()

func _piece(center:Vector2, code:String, alpha := 1.0):
    # V0.12: peças com contraste/volume reforçados e pixelização menos destrutiva.
    if alpha <= 0.0: return
    if piece_textures.has(code) and piece_textures[code]:
        var tex:Texture2D = piece_textures[code]
        var heights = {"P":46.0,"R":54.0,"N":57.0,"B":60.0,"Q":64.0,"K":66.0}
        var height: float = heights[code.substr(1,1)]
        var size := Vector2(39.0 if code.ends_with("P") else 47.0, height)
        # Uma única sombra neutra; sem glow/outline artificial.
        draw_ellipse_shadow(center + Vector2(0,26), Vector2(size.x*0.42,3), Color(0.02,0.025,0.015,0.28*alpha))
        draw_texture_rect(tex, Rect2(Vector2(center.x-size.x/2.0, center.y+27.0-size.y), size), false, Color(1,1,1,alpha))
        return

func draw_ellipse_shadow(c:Vector2,r:Vector2,col:Color):
    var pts=PackedVector2Array()
    for i in range(20):
        var a=TAU*float(i)/20.0
        pts.append(c+Vector2(cos(a)*r.x,sin(a)*r.y))
    draw_colored_polygon(pts,col)

func _draw_pixel_ellipse(c:Vector2,r:Vector2,col:Color):
    var pts=PackedVector2Array()
    for i in range(20):
        var a=TAU*i/20.0
        pts.append(c+Vector2(cos(a)*r.x,sin(a)*r.y))
    draw_colored_polygon(pts,col)

func _draw_ui():
    if mobile_presentation: return
    var font=ThemeDB.fallback_font
    if external_hud:
        if not game_started: draw_rect(presentation_rect,Color(0,0,0,0.20))
        _draw_status_and_settings(font)
        return
    # Engrenagem discreta no canto superior direito.
    draw_rect(gear_button, Color(0.08,0.07,0.05,0.72))
    draw_rect(gear_button, Color("#b99555"), false, 1)
    var gc=gear_button.get_center()
    draw_circle(gc, 8, Color("#d6bd82"), false, 3)
    draw_circle(gc, 2.5, Color("#d6bd82"))
    for i in range(8):
        var a=TAU*float(i)/8.0
        var d=Vector2(cos(a),sin(a))
        draw_line(gc+d*9,gc+d*13,Color("#d6bd82"),3)

    if game_started:
        draw_rect(restart_button, Color(0.08,0.07,0.05,0.68))
        draw_rect(restart_button, Color("#9e8150"), false, 1)
        draw_string(font,restart_button.position+Vector2(15,23),"REINICIAR",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#e6d6ad"))
    else:
        # Tela inicial sem esconder o mapa: apenas escurece levemente e mostra um botão pequeno.
        draw_rect(presentation_rect,Color(0,0,0,0.20))

    _draw_status_and_settings(font)

func _draw_status_and_settings(font):
    if game_started and not hide_status:
        var label_width = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
        draw_style_box(_panel_style(), Rect2(512-label_width/2-18, 851, label_width+36, 38))
        draw_string(font,Vector2(512-label_width/2,877),status,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#eee0bc"))

    if settings_open:
        var panel=settings_panel
        var frame := StyleBoxFlat.new()
        frame.bg_color = Color(0.06,0.13,0.09,0.95)
        frame.border_color = Color("#b99555")
        frame.set_border_width_all(2)
        frame.set_corner_radius_all(8)
        frame.shadow_color = Color(0,0,0,0.45)
        frame.shadow_size = 6
        draw_style_box(frame, panel)
        draw_string(font,panel.position+Vector2(16,27),"OPÇÕES DA PARTIDA",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#f4ce7f"))
        draw_string(font,panel.position+Vector2(16,53),"M • ativar / silenciar música",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#d5ccb9"))
        draw_style_box(_panel_style(), fullscreen_button)
        var fullscreen_on = get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
        var caption = "Tela Cheia: " + ("Sim" if fullscreen_on else "Não")
        draw_string(font,fullscreen_button.position+Vector2(10,24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#eee0bc"))
        draw_string(font,panel.position+Vector2(16,125),"Alt+Enter • alternar",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#d5ccb9"))

func _draw():
    if visual_theme != "wood":
        var edge = Rect2(ORIGIN-Vector2(10,10),Vector2(BOARD+20,BOARD+20))
        draw_rect(edge,Color("161e25"))
        draw_rect(edge,Color("929a9c"),false,3)
        if visual_theme == "bronze":
            # A square rim in the same coordinate system as all 64 cells.
            var bronze_edge = Rect2(ORIGIN-Vector2(20,20),Vector2(BOARD+40,BOARD+40))
            draw_rect(bronze_edge,Color("34251a"))
            draw_rect(bronze_edge,Color("b77a39"),false,7)
            draw_rect(bronze_edge.grow(-8),Color("e4b775"),false,2)
            for corner in [bronze_edge.position,Vector2(bronze_edge.end.x,bronze_edge.position.y),bronze_edge.end,Vector2(bronze_edge.position.x,bronze_edge.end.y)]:
                draw_rect(Rect2(corner-Vector2(7,7),Vector2(14,14)),Color("e4b775"))
                draw_rect(Rect2(corner-Vector2(3,3),Vector2(6,6)),Color("6c421d"))
    var cosmetic = preload("res://cosmetics/theme_catalog.gd").get_theme(visual_theme)
    if cosmetic.get("free_arena",false):
        preload("res://cosmetics/league_board.gd").draw_frame(self,ORIGIN,BOARD,visual_theme,cosmetic.rim)
    var check_sq := _check_square()
    for y in range(8):
        for x in range(8):
            var c=Vector2i(x,y)
            var r=Rect2(ORIGIN+Vector2(display_cell(c))*TILE,Vector2(TILE,TILE))
            var sq=Color("#cbb273") if (x+y)%2==0 else Color("#557a3e")
            if visual_theme != "wood":
                # Cosmetic steel tiles share the exact existing input grid.
                draw_rect(r,board_palette[(x+y)%2])
                draw_line(r.position,r.position+Vector2(TILE,0),Color(1,1,1,0.13),2)
                draw_line(r.position,r.position+Vector2(0,TILE),Color(1,1,1,0.09),2)
                draw_line(r.end-Vector2(TILE,1),r.end-Vector2(0,1),Color(0,0,0,0.21),2)
            # The playable surface belongs to the dedicated forest artwork.
            if c==last_from or c==last_to:
                _draw_last_move(r, c==last_to)
            if c==premove_from or c==premove_to:
                draw_rect(r,PREMOVE_TINT)
            if c==check_sq:
                _draw_check_glow(r)
            if c in legal_moves:
                if premove_selecting:
                    draw_circle(r.get_center(),8,Color(0.45,0.70,1.0,0.80))
                elif pieces.has(c):
                    draw_rect(r.grow(-6),Color("#d94f3d"),false,5)
                else:
                    draw_circle(r.get_center(),8,Color(0.95,0.83,0.35,0.82))
            if c==selected:
                draw_rect(r.grow(-4),Color("#f3d25c"),false,5)

    # Sem letras/números: arena limpa como a referência (exceto no LABORATÓRIO, opcional).
    if show_coordinates: _draw_coordinates()

    var pre_on := premove_from!=Vector2i(-1,-1) and pieces.has(premove_from)
    for f in move_fades:
        _piece(f.at, f.code, 1.0 - _ease_move(move_anim_t))
    for pos in pieces:
        if dragging and pos == drag_origin:
            continue
        if pre_on and (pos == premove_from or pos == premove_to):
            continue
        if move_hidden.has(pos):
            continue
        _piece(square_center(pos),pieces[pos])
    for m in move_anim:
        # R38 · desliza em arco suave (sobe um pouco e assenta na casa)
        var lift := Vector2(0, -sin(PI * move_anim_t) * TILE * MOVE_LIFT)
        _piece(m.from.lerp(m.to, _ease_move(move_anim_t)) + lift, m.code)
    if pre_on:
        # A peça já aparece na casa do pré-move (como no Chess.com).
        _piece(square_center(premove_to),pieces[premove_from])

    if dragging and pieces.has(drag_origin):
        _piece(drag_position, pieces[drag_origin])

    if flash>0:
        draw_circle(flash_pos,35*(1.0-flash)+12,Color(1,.78,.25,flash*.32),false,5)
    for p in particles:
        var a=clamp(float(p["life"])*2.0,0.0,1.0)
        var cc:Color=p["col"]
        cc.a=a
        draw_rect(Rect2(p["pos"]-Vector2(3,3),Vector2(6,6)),cc)


    _draw_promotion_overlay()
    _draw_ui()

func _captured_text(a:Array[String])->String:
    if a.is_empty(): return "—"
    var s=""
    for v in a: s+=v.substr(1,1)+" "
    return s

func _select(cell:Vector2i):
    if _premove_mode():
        var me := _premove_color()
        if pieces.has(cell) and _color_at(cell)==me:
            selected=cell
            legal_moves=_premove_targets(cell)
            premove_selecting=true
        else:
            selected=Vector2i(-1,-1); legal_moves.clear(); premove_selecting=false
        return
    if bot != null and not bot.can_interact(): return
    if online != null and not online.can_interact():
        return
    if game_over: return
    if pieces.has(cell) and _color_at(cell)==turn:
        selected=cell
        legal_moves=_moves(cell)
        # Em xeque e a peça não tem lance: o rei pisca em vermelho para mostrar o motivo.
        if legal_moves.is_empty() and _check_square()!=Vector2i(-1,-1): check_flash=1.0
    else:
        selected=Vector2i(-1,-1); legal_moves.clear()

func _unhandled_input(event):
    # Presentation actions precede all game states, including promotion and mate.
    if event is InputEventKey and event.pressed and event.alt_pressed and event.keycode == KEY_ENTER:
        if not event.echo:
            get_parent().toggle_fullscreen()
        get_viewport().set_input_as_handled()
        return
    if online != null and event is InputEventKey and event.pressed and event.keycode == KEY_R:
        online.send_action("restart")
        return
    var local_event = make_input_local(event)
    if local_event is InputEventMouseButton and local_event.button_index == MOUSE_BUTTON_LEFT and local_event.pressed and settings_open:
        if fullscreen_button.has_point(local_event.position):
            get_parent().toggle_fullscreen()
            get_viewport().set_input_as_handled()
            return
        if settings_panel.has_point(local_event.position):
            return
    if _drag_input(local_event):
        return
    _handle_game_input(local_event)

func _handle_game_input(event):
    if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
        if premove_from!=Vector2i(-1,-1) or premove_selecting:
            clear_premove()
            return
    if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
        if not mobile_presentation and not external_hud and gear_button.has_point(event.position):
            settings_open = not settings_open
            cancel_drag()
            selected = Vector2i(-1,-1)
            legal_moves.clear()
            queue_redraw()
            return
        if settings_open: return
        if not game_started:
            if start_button.has_point(event.position):
                game_started = true
                settings_open = false
                _new_game()
                queue_redraw()
            return
        if not mobile_presentation and not external_hud and restart_button.has_point(event.position):
            _new_game()
            queue_redraw()
            return
    if settings_open: return
    if not game_started:
        if event is InputEventKey and event.pressed and (event.keycode==KEY_ENTER or event.keycode==KEY_SPACE):
            game_started=true
            _new_game()
        return
    if game_over:
        if event is InputEventKey and event.pressed and event.keycode==KEY_R: _new_game()
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_M:
        var audio = get_parent().get_node_or_null("GameAudio")
        if audio != null: audio.toggle_music()
        return
    if event is InputEventKey and event.pressed:
        if event.keycode==KEY_R and not promotion_pending:
            _new_game()
            return
        if promotion_pending:
            if event.keycode==KEY_1: _finish_promotion("Q")
            elif event.keycode==KEY_2: _finish_promotion("R")
            elif event.keycode==KEY_3: _finish_promotion("B")
            elif event.keycode==KEY_4: _finish_promotion("N")
            return
    if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
        if promotion_pending:
            if mobile_presentation: return
            var opts=["Q","R","B","N"]
            for i in range(4):
                var rr=Rect2(269+i*130,473,105,95)
                if rr.has_point(event.position):
                    _finish_promotion(opts[i])
                    return
            return
        var local=event.position-ORIGIN
        if local.x<0 or local.y<0 or local.x>=BOARD or local.y>=BOARD: return
        var cell=cell_at(event.position)
        if _premove_mode():
            _premove_click(cell)
            queue_redraw()
            return
        if selected==Vector2i(-1,-1):
            _select(cell)
        elif cell==selected:
            selected=Vector2i(-1,-1); legal_moves.clear()
        elif cell in legal_moves:
            _drag_submit = [selected, cell] if dragging else []
            if bot != null:
                bot.request_move(selected,cell)
                return
            if online != null:
                online.send_action("move", {"from":[selected.x,selected.y],"to":[cell.x,cell.y]})
                return
            var moving:String=pieces[selected]
            var did_capture=false
            if pieces.has(cell):
                var victim:String=pieces[cell]
                if victim.substr(0,1)=="w": captured_white.append(victim)
                else: captured_black.append(victim)
                _spawn_capture(square_center(cell),victim)
                did_capture=true
            var before_local := pieces.duplicate()
            pieces.erase(selected)
            pieces[cell]=moving
            last_from=selected; last_to=cell
            show_move(before_local, selected, cell, true, dragging)
            selected=Vector2i(-1,-1); legal_moves.clear()
            move_count+=1
            # promotion: stop and ask before the next board interaction
            if moving.substr(1,1)=="P" and ((moving.substr(0,1)=="w" and cell.y==0) or (moving.substr(0,1)=="b" and cell.y==7)):
                promotion_pending=true
                promotion_cell=cell
                promotion_color=moving.substr(0,1)
            turn="b" if turn=="w" else "w"
            if not promotion_pending:
                _update_game_state()
        elif pieces.has(cell) and _color_at(cell)==turn:
            _select(cell)
        else:
            selected=Vector2i(-1,-1); legal_moves.clear()
        queue_redraw()

func _panel_style() -> StyleBoxFlat:
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.06,0.13,0.09,0.94)
    style.border_color = Color("#b99555")
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    style.shadow_color = Color(0,0,0,0.4)
    style.shadow_size = 5
    return style

func _exit_tree():
    for player in [sound_move, sound_capture, sound_promotion, sound_ambient, sound_water]:
        if is_instance_valid(player):
            player.stop()
            player.stream = null

func toggle_settings():
    settings_open = not settings_open
    cancel_drag()
    selected = Vector2i(-1,-1)
    legal_moves.clear()
    queue_redraw()

func restart_match():
    _new_game()
    queue_redraw()

func place_settings_panel(top_right: Vector2):
    settings_panel = Rect2(top_right.x-252.0, top_right.y, 252, 136)
    fullscreen_button = Rect2(settings_panel.position+Vector2(12,65), Vector2(228,38))
    queue_redraw()

func update_presentation(view_rect: Rect2):
    cancel_drag()
    presentation_rect = view_rect
    var right = view_rect.end.x - 16.0
    var top = view_rect.position.y + 18.0
    gear_button = Rect2(right-34.0, top, 34, 34)
    restart_button = Rect2(right-156.0, top, 112, 34)
    settings_panel = Rect2(right-252.0, top+42.0, 252, 136)
    fullscreen_button = Rect2(settings_panel.position+Vector2(12,65), Vector2(228,38))
    queue_redraw()

func _drag_input(event: InputEvent) -> bool:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            cancel_drag()
            var pre := _premove_mode()
            if not pre and (not game_started or game_over or promotion_pending or settings_open or (online != null and not online.can_interact()) or (bot != null and not bot.can_interact())):
                return false
            var cell = cell_at(event.position)
            if _inside(cell) and pieces.has(cell) and _color_at(cell) == (_premove_color() if pre else turn):
                drag_origin = cell
                drag_start = event.position
                drag_position = event.position
            return false
        if drag_origin != Vector2i(-1, -1):
            if dragging:
                var cell = cell_at(event.position)
                if cell in legal_moves:
                    var drop = InputEventMouseButton.new()
                    drop.button_index = MOUSE_BUTTON_LEFT
                    drop.pressed = true
                    drop.position = event.position
                    _handle_game_input(drop)
            cancel_drag()
            return true
    if event is InputEventMouseMotion and drag_origin != Vector2i(-1, -1):
        if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
            cancel_drag()
            return false
        drag_position = event.position
        if not dragging and drag_start.distance_to(drag_position) >= 6.0:
            dragging = true
            _select(drag_origin)
        queue_redraw()
        return dragging
    return false

## Mostra um lance JÁ aplicado em `pieces`: anima quem mudou de casa (inclui roque e en passant) e
## destaca origem/destino. `before` = tabuleiro antes do lance. `emphasize` = lance do adversário,
## do bot ou recebido do servidor (destaque forte que esmaece). Puramente visual: nenhuma regra, nenhum
## motor — só compara os dois tabuleiros que o jogo já tem.
func show_move(before: Dictionary, from: Vector2i, to: Vector2i, emphasize: bool, by_drag := false):
    _finish_move_anim()
    last_from = from
    last_to = to
    last_move_emph = emphasize
    last_move_age = 0.0
    if not before.has(from): return
    var own_drag: bool = by_drag or (_drag_submit.size() == 2 and _drag_submit[0] == from and _drag_submit[1] == to and not emphasize)
    _drag_submit = []
    if own_drag: return   # a peça já foi levada com o mouse/dedo até a casa
    var mover := String(before[from])
    var color := mover.substr(0, 1)
    move_anim.append({"code": mover, "from": square_center(from), "to": square_center(to)})
    move_hidden[to] = true
    # Outras peças da MESMA cor que mudaram de casa (torre do roque).
    var left := []
    var arrived := []
    for sq in before:
        if sq == from: continue
        var code := String(before[sq])
        if code.substr(0, 1) == color and String(pieces.get(sq, "")) != code: left.append(sq)
    for sq in pieces:
        if sq == to: continue
        var code := String(pieces[sq])
        if code.substr(0, 1) == color and String(before.get(sq, "")) != code: arrived.append(sq)
    for a in left:
        for b in arrived:
            if String(before[a]) == String(pieces[b]):
                move_anim.append({"code": String(before[a]), "from": square_center(a), "to": square_center(b)})
                move_hidden[b] = true
                arrived.erase(b)
                break
    # Peças do adversário que sumiram (captura normal na casa de destino, en passant ao lado):
    # esmaecem durante o deslocamento, em vez de piscar.
    for sq in before:
        var code := String(before[sq])
        if code.substr(0, 1) != color and String(pieces.get(sq, "")) != code:
            move_fades.append({"code": code, "at": square_center(sq)})
    var dist := maxf(absf(to.x - from.x), absf(to.y - from.y))
    move_anim_len = (MOVE_ANIM if emphasize else OWN_MOVE_ANIM) + minf(0.25, maxf(0.0, dist - 1.0) * MOVE_PER_SQUARE)
    move_anim_t = 0.0
    queue_redraw()

func move_animating() -> bool:
    return move_anim_t < 1.0

func _finish_move_anim():
    move_anim.clear()
    move_fades.clear()
    move_hidden.clear()
    move_anim_t = 1.0

## Sem lance anterior (nova partida / reconexão): nenhum destaque antigo fica no tabuleiro.
func clear_last_move():
    _finish_move_anim()
    last_from = Vector2i(-1,-1)
    last_to = Vector2i(-1,-1)
    last_move_emph = false
    last_move_age = 99.0

static func _ease_move(t: float) -> float:
    # ease-in-out cúbico: sai devagar, desliza e "assenta" na casa
    return 4.0*t*t*t if t < 0.5 else 1.0 - pow(-2.0*t + 2.0, 3.0) / 2.0

## Origem dourada suave; destino dourado-esverdeado mais forte. Lance do adversário/remoto: forte por
## LAST_MOVE_HOLD s, esmaece em LAST_MOVE_FADE s (ou logo que o jogador escolhe uma peça) até um tom
## residual discreto que marca o último lance. Lance próprio: só o tom residual.
func _draw_coordinates():
    var font := ThemeDB.fallback_font
    var fsz := int(TILE * 0.2)
    for i in range(8):
        # colunas (a–h) na fileira de baixo da tela; fileiras (1–8) na coluna da esquerda
        var file_cell := Vector2i(i, 7) if not board_flipped() else Vector2i(7 - i, 0)
        var fr := Rect2(ORIGIN + Vector2(display_cell(file_cell)) * TILE, Vector2(TILE, TILE))
        var ink: Color = board_palette[(file_cell.x + file_cell.y) % 2 ^ 1] if visual_theme != "wood" else Color(0.1, 0.12, 0.08, 0.85)
        draw_string(font, fr.end - Vector2(TILE * 0.2, TILE * 0.06), "abcdefgh"[file_cell.x], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(ink, 0.9))
        var rank_cell := Vector2i(0, i) if not board_flipped() else Vector2i(7, 7 - i)
        var rr := Rect2(ORIGIN + Vector2(display_cell(rank_cell)) * TILE, Vector2(TILE, TILE))
        var ink2: Color = board_palette[(rank_cell.x + rank_cell.y) % 2 ^ 1] if visual_theme != "wood" else Color(0.1, 0.12, 0.08, 0.85)
        draw_string(font, rr.position + Vector2(TILE * 0.06, TILE * 0.24), str(8 - rank_cell.y), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(ink2, 0.9))

func _draw_last_move(r: Rect2, dest: bool):
    var base := 0.20 if dest else 0.15
    var strong := 0.0
    if last_move_emph:
        var hold := LAST_MOVE_HOLD if selected == Vector2i(-1,-1) else minf(LAST_MOVE_HOLD, 0.25)
        strong = 1.0 - clampf((last_move_age - hold) / LAST_MOVE_FADE, 0.0, 1.0)
    var col: Color = HL_TO if dest else HL_FROM
    var a := base + strong * (0.28 if dest else 0.22)
    draw_rect(r.grow(-2), Color(col.r, col.g, col.b, a))
    # contorno: forte logo após o lance; depois um fio discreto (as casas claras são da cor do dourado)
    var edge := maxf(strong * (0.85 if dest else 0.65), 0.38 if dest else 0.30)
    draw_rect(r.grow(-3), Color(col.r * 0.85, col.g * 0.75, col.b * 0.5, edge), false, 3.0 if (dest and strong > 0.5) else 2.0)

func cancel_drag():
    drag_origin = Vector2i(-1,-1)
    dragging = false
    queue_redraw()

func _notification(what):
    if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        cancel_drag()

# ---------- Xeque ----------
## Casa do rei de quem está na vez, se estiver em xeque (inclui xeque-mate).
func _check_square() -> Vector2i:
    if not game_started or pieces.is_empty(): return Vector2i(-1,-1)
    var king=_find_king(turn)
    if king==Vector2i(-1,-1): return king
    return king if _square_attacked(king,"b" if turn=="w" else "w") else Vector2i(-1,-1)

func _draw_check_glow(r: Rect2):
    var pulse := 0.5+0.5*sin(anim_time*5.0)
    var c := r.get_center()
    # Brilho vermelho em volta do rei (sem texto e sem som).
    draw_rect(r,Color(0.85,0.08,0.05,0.22+0.10*pulse+check_flash*0.25))
    for i in range(6):
        var k := 1.0-float(i)/6.0
        draw_circle(c,TILE*(0.14+0.065*i),Color(1.0,0.15,0.08,(0.16+0.08*pulse)*k+check_flash*0.12))
    draw_rect(r.grow(-2),Color(1.0,0.22,0.15,0.75+0.25*pulse),false,4.0+check_flash*3.0)
    if check_flash>0.0:
        draw_rect(r.grow(4.0*check_flash),Color(1.0,0.25,0.18,check_flash*0.9),false,3.0)

# ---------- Pré-move ----------
## Cor do jogador humano quando o pré-move pode ser usado nesta partida; "" se não.
func _premove_color() -> String:
    if not premove_enabled or bot == null or not game_started or game_over or settings_open: return ""
    if bool(bot.get("local_mode")): return ""
    if not bool(bot.get("active")): return ""
    var st = bot.get("status")
    if st != null and String(st) not in ["playing","starting"]: return ""
    return String(bot.human_color)

## Vez do adversário (ou lance seu ainda a caminho do servidor): cliques viram pré-move.
func _premove_mode() -> bool:
    return _premove_color()!="" and not promotion_pending and not bot.can_interact()

func clear_premove():
    premove_from=Vector2i(-1,-1)
    premove_to=Vector2i(-1,-1)
    if premove_selecting:
        selected=Vector2i(-1,-1); legal_moves.clear()
    premove_selecting=false
    queue_redraw()

func _premove_click(cell: Vector2i):
    var me := _premove_color()
    var own := pieces.has(cell) and _color_at(cell)==me
    if premove_from!=Vector2i(-1,-1) and not premove_selecting:
        # Já havia um pré-move: clicar em outro lugar cancela; numa peça sua, escolhe de novo.
        clear_premove()
        if own: _select(cell)
        return
    if selected==Vector2i(-1,-1) or not premove_selecting:
        _select(cell)
    elif cell==selected:
        clear_premove()
    elif cell in legal_moves:
        premove_from=selected
        premove_to=cell
        selected=Vector2i(-1,-1); legal_moves.clear(); premove_selecting=false
    elif own:
        _select(cell)
    else:
        clear_premove()

## Casas para onde a peça poderia ir (o adversário ainda vai jogar, então só as suas peças bloqueiam).
func _premove_targets(fr: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var code: String = pieces.get(fr,"")
    if code.is_empty(): return out
    var me := code.substr(0,1)
    var kind := code.substr(1,1)
    var add := func(q: Vector2i):
        if _inside(q) and _color_at(q)!=me and q not in out: out.append(q)
    match kind:
        "P":
            var dy := -1 if me=="w" else 1
            var one := fr+Vector2i(0,dy)
            if _inside(one) and _color_at(one)!=me:
                add.call(one)
                var start := 6 if me=="w" else 1
                if fr.y==start and not pieces.has(one): add.call(fr+Vector2i(0,2*dy))
            add.call(fr+Vector2i(-1,dy)); add.call(fr+Vector2i(1,dy))
        "N":
            for d in [Vector2i(1,2),Vector2i(2,1),Vector2i(2,-1),Vector2i(1,-2),Vector2i(-1,-2),Vector2i(-2,-1),Vector2i(-2,1),Vector2i(-1,2)]:
                add.call(fr+d)
        "K":
            for yy in range(-1,2):
                for xx in range(-1,2):
                    if xx!=0 or yy!=0: add.call(fr+Vector2i(xx,yy))
            var home := 7 if me=="w" else 0
            if fr==Vector2i(4,home):
                if pieces.get(Vector2i(7,home),"")==me+"R": add.call(Vector2i(6,home))
                if pieces.get(Vector2i(0,home),"")==me+"R": add.call(Vector2i(2,home))
        _:
            var dirs := []
            if kind in ["R","Q"]: dirs += [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
            if kind in ["B","Q"]: dirs += [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
            for d in dirs:
                var q: Vector2i = fr+d
                while _inside(q) and _color_at(q)!=me:
                    out.append(q)
                    q+=d
    return out

## Chegou a sua vez: joga o pré-move se ainda for legal (promoção vira Dama), senão descarta.
func _premove_tick():
    if premove_from==Vector2i(-1,-1) and not premove_selecting: return
    if _premove_color()=="":
        clear_premove()
        return
    if not bot.can_interact(): return
    if premove_selecting:
        # A seleção feita na vez do adversário vira seleção normal.
        premove_selecting=false
        if selected!=Vector2i(-1,-1) and _color_at(selected)==turn: legal_moves=_moves(selected)
        else: selected=Vector2i(-1,-1); legal_moves.clear()
    if premove_from==Vector2i(-1,-1): return
    var f := premove_from
    var t := premove_to
    premove_from=Vector2i(-1,-1)
    premove_to=Vector2i(-1,-1)
    if _color_at(f)!=turn: return
    selected=Vector2i(-1,-1); legal_moves.clear()
    if bot.request_move(f,t) and promotion_pending and bot.promotion_choices.size()>1:
        bot.promote("Q")
    queue_redraw()
