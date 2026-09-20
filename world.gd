extends Node2D

# V0.17 CLEAN: camada visual simplificada; regras preservadas.
var tile_light_tex = preload("res://visual_v014/tile_light.png")
var tile_dark_tex = preload("res://visual_v014/tile_dark.png")

const TILE := 75
const BOARD := TILE * 8
const ORIGIN := Vector2(210,186)
var arena_bg: Texture2D
var piece_textures := {}

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
    sound_ambient = AudioStreamPlayer.new()
    add_child(sound_ambient)
    sound_ambient.stream = load("res://audio/forest_ambient.wav")
    sound_ambient.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    sound_ambient.stream.loop_begin = 0
    sound_ambient.stream.loop_end = int(sound_ambient.stream.get_length()*sound_ambient.stream.mix_rate)
    sound_ambient.volume_db = -70.0
    sound_ambient.play()
    create_tween().tween_property(sound_ambient,"volume_db",-28.0,2.5)
    _new_game()
    set_process(true)

func _new_game():
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
    last_from = Vector2i(-1,-1)
    last_to = Vector2i(-1,-1)
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
    # cenário vivo: redesenha continuamente para água, fogo e vegetação
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
    if online != null:
        online.send_action("promote", {"kind":kind})
        return
    if not promotion_pending: return
    pieces[promotion_cell]=promotion_color+kind
    promotion_pending=false
    promotion_cell=Vector2i(-1,-1)
    _update_game_state()
    queue_redraw()

func _piece(center:Vector2, code:String):
    # V0.12: peças com contraste/volume reforçados e pixelização menos destrutiva.
    if piece_textures.has(code) and piece_textures[code]:
        var tex:Texture2D = piece_textures[code]
        var heights = {"P":46.0,"R":54.0,"N":57.0,"B":60.0,"Q":64.0,"K":66.0}
        var height: float = heights[code.substr(1,1)]
        var size := Vector2(39.0 if code.ends_with("P") else 47.0, height)
        # Uma única sombra neutra; sem glow/outline artificial.
        draw_ellipse_shadow(center + Vector2(0,22), Vector2(18,5), Color(0.02,0.025,0.015,0.18))
        draw_texture_rect(tex, Rect2(Vector2(center.x-size.x/2.0, center.y+27.0-size.y), size), false)
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
    var font=ThemeDB.fallback_font
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

    if game_started:
        var label_width = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
        draw_style_box(_panel_style(), Rect2(512-label_width/2-18, 851, label_width+36, 38))
        draw_string(font,Vector2(512-label_width/2,877),status,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#eee0bc"))

    if settings_open:
        var panel=settings_panel
        draw_rect(panel,Color(0.07,0.06,0.05,0.92))
        draw_rect(panel,Color("#9e8150"),false,1)
        draw_string(font,panel.position+Vector2(16,27),"CONFIGURAÇÕES",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#e8d6a8"))
        draw_string(font,panel.position+Vector2(16,53),"M • ativar / silenciar ambiente",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#d5ccb9"))
        draw_style_box(_panel_style(), fullscreen_button)
        var fullscreen_on = get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
        var caption = "Tela Cheia: " + ("Sim" if fullscreen_on else "Não")
        draw_string(font,fullscreen_button.position+Vector2(10,24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#eee0bc"))
        draw_string(font,panel.position+Vector2(16,125),"Alt+Enter • alternar",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#d5ccb9"))

func _draw():
    for y in range(8):
        for x in range(8):
            var c=Vector2i(x,y)
            var r=Rect2(ORIGIN+Vector2(x,y)*TILE,Vector2(TILE,TILE))
            var sq=Color("#cbb273") if (x+y)%2==0 else Color("#557a3e")
            # The playable surface belongs to the dedicated forest artwork.
            if c==last_from or c==last_to:
                draw_rect(r.grow(-3),Color(1.0,0.78,0.20,0.26))
            if c in legal_moves:
                if pieces.has(c):
                    draw_rect(r.grow(-6),Color("#d94f3d"),false,5)
                else:
                    draw_circle(r.get_center(),8,Color(0.95,0.83,0.35,0.82))
            if c==selected:
                draw_rect(r.grow(-4),Color("#f3d25c"),false,5)

    # Sem letras/números: arena limpa como a referência.

    for pos in pieces:
        if dragging and pos == drag_origin:
            continue
        _piece(ORIGIN+Vector2(pos.x*TILE+TILE/2.0,pos.y*TILE+TILE/2.0),pieces[pos])

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
    if online != null and not online.can_interact():
        return
    if game_over: return
    if pieces.has(cell) and _color_at(cell)==turn:
        selected=cell
        legal_moves=_moves(cell)
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
    if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
        if gear_button.has_point(event.position):
            settings_open = not settings_open
            queue_redraw()
            return
        if not game_started:
            if start_button.has_point(event.position):
                game_started = true
                settings_open = false
                _new_game()
                queue_redraw()
            return
        if restart_button.has_point(event.position):
            _new_game()
            queue_redraw()
            return
    if not game_started:
        if event is InputEventKey and event.pressed and (event.keycode==KEY_ENTER or event.keycode==KEY_SPACE):
            game_started=true
            _new_game()
        return
    if game_over:
        if event is InputEventKey and event.pressed and event.keycode==KEY_R: _new_game()
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_M:
        sound_ambient.stream_paused = not sound_ambient.stream_paused
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
            var opts=["Q","R","B","N"]
            for i in range(4):
                var rr=Rect2(269+i*130,473,105,95)
                if rr.has_point(event.position):
                    _finish_promotion(opts[i])
                    return
            return
        var local=event.position-ORIGIN
        if local.x<0 or local.y<0 or local.x>=BOARD or local.y>=BOARD: return
        var cell=Vector2i(int(local.x/TILE),int(local.y/TILE))
        if selected==Vector2i(-1,-1):
            _select(cell)
        elif cell==selected:
            selected=Vector2i(-1,-1); legal_moves.clear()
        elif cell in legal_moves:
            if online != null:
                online.send_action("move", {"from":[selected.x,selected.y],"to":[cell.x,cell.y]})
                return
            var moving:String=pieces[selected]
            var did_capture=false
            if pieces.has(cell):
                var victim:String=pieces[cell]
                if victim.substr(0,1)=="w": captured_white.append(victim)
                else: captured_black.append(victim)
                _spawn_capture(ORIGIN+Vector2(cell.x*TILE+TILE/2.0,cell.y*TILE+TILE/2.0),victim)
                did_capture=true
            pieces.erase(selected)
            pieces[cell]=moving
            last_from=selected; last_to=cell
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
    style.bg_color = Color(0.055,0.085,0.045,0.92)
    style.border_color = Color("#a78b50")
    style.set_border_width_all(1)
    style.set_corner_radius_all(5)
    return style

func _exit_tree():
    for player in [sound_move, sound_capture, sound_promotion, sound_ambient, sound_water]:
        if is_instance_valid(player):
            player.stop()
            player.stream = null

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
            if not game_started or game_over or promotion_pending or settings_open or (online != null and not online.can_interact()):
                return false
            var cell = Vector2i(floor((event.position.x-ORIGIN.x)/TILE), floor((event.position.y-ORIGIN.y)/TILE))
            if _inside(cell) and pieces.has(cell) and _color_at(cell) == turn:
                drag_origin = cell
                drag_start = event.position
                drag_position = event.position
            return false
        if drag_origin != Vector2i(-1, -1):
            if dragging:
                var cell = Vector2i(floor((event.position.x-ORIGIN.x)/TILE), floor((event.position.y-ORIGIN.y)/TILE))
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

func cancel_drag():
    drag_origin = Vector2i(-1,-1)
    dragging = false
    queue_redraw()

func _notification(what):
    if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        cancel_drag()
