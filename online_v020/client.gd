extends CanvasLayer
var game
var socket: WebSocketPeer
var endpoint=""
var room=""
var color=""
var token=""
var revision=0
var online_mode=false
var connected=false
var joined=false
var both_connected=false
var started=false
var pending=false
var leaving=false
var greeting={}
var retry_after=0.0
var elapsed=0.0
var ping_at=0.0
var message=""
var saved={}
var menu: PanelContainer
var hud: PanelContainer
var menu_info: Label
var hud_info: Label
var room_input: LineEdit
var reconnect_button: Button
var restart_button: Button
var exit_dialog: ConfirmationDialog

func _ready():
    game=get_parent().get_node("World")
    layer=20
    var config=ConfigFile.new()
    if config.load("res://online.cfg")==OK: endpoint=String(config.get_value("online","server_url",""))
    if config.load(OS.get_executable_path().get_base_dir()+"/online.cfg")==OK: endpoint=String(config.get_value("online","server_url",endpoint))
    if OS.has_environment("FRAIHA_SERVER_URL"): endpoint=OS.get_environment("FRAIHA_SERVER_URL")
    var session=ConfigFile.new()
    if session.load("user://online_session.cfg")==OK:
        saved={"room":session.get_value("session","room",""),"token":session.get_value("session","token","")}
    build_ui()

func panel_style()->StyleBoxFlat:
    var style=StyleBoxFlat.new()
    style.bg_color=Color("#142217f2")
    style.border_color=Color("#b19758")
    style.set_border_width_all(2)
    style.set_corner_radius_all(7)
    style.content_margin_left=22; style.content_margin_right=22
    style.content_margin_top=18; style.content_margin_bottom=18
    return style

func button(parent:Control,caption:String,callback:Callable)->Button:
    var b=Button.new()
    b.text=caption
    b.custom_minimum_size=Vector2(0,44)
    b.add_theme_font_size_override("font_size",18)
    parent.add_child(b)
    b.pressed.connect(callback)
    return b

func build_ui():
    var control=Control.new()
    control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    control.mouse_filter=Control.MOUSE_FILTER_IGNORE
    add_child(control)
    menu=PanelContainer.new()
    control.add_child(menu)
    menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    menu.offset_left=-250; menu.offset_right=250
    menu.offset_top=-210; menu.offset_bottom=210
    menu.add_theme_stylebox_override("panel",panel_style())
    var box=VBoxContainer.new()
    box.add_theme_constant_override("separation",10)
    menu.add_child(box)
    var title=Label.new()
    title.text="FRAIHA • XADREZ"
    title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size",27)
    box.add_child(title)
    button(box,"Jogar local • duas pessoas",start_local)
    button(box,"Criar Sala",func(): connect_room({"type":"create"}))
    var row=HBoxContainer.new(); box.add_child(row)
    room_input=LineEdit.new()
    room_input.placeholder_text="Código da sala"
    room_input.max_length=6
    room_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    row.add_child(room_input)
    button(row,"Entrar na Sala",func(): connect_room({"type":"join","room":room_input.text.strip_edges().to_upper()}))
    reconnect_button=button(box,"Reconectar à última sala",resume_room)
    reconnect_button.visible=not saved.is_empty()
    menu_info=Label.new()
    menu_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    menu_info.custom_minimum_size.x=440
    menu_info.text="Jogue localmente ou compartilhe uma sala com um amigo."
    if endpoint.is_empty(): menu_info.text="Jogo local disponível. As salas online aguardam a publicação do servidor."
    box.add_child(menu_info)
    hud=PanelContainer.new()
    hud.position=Vector2(18,18)
    hud.custom_minimum_size=Vector2(385,0)
    hud.add_theme_stylebox_override("panel",panel_style())
    control.add_child(hud)
    var hbox=VBoxContainer.new(); hud.add_child(hbox)
    hud_info=Label.new()
    hud_info.custom_minimum_size.x=345
    hud_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    hbox.add_child(hud_info)
    var buttons=HBoxContainer.new(); hbox.add_child(buttons)
    button(buttons,"Copiar código",func(): DisplayServer.clipboard_set(room))
    restart_button=button(buttons,"Revanche",func(): send_action("restart"))
    button(hbox,"Desistir / voltar ao menu",func(): exit_dialog.popup_centered())
    hud.hide()
    exit_dialog=ConfirmationDialog.new()
    exit_dialog.dialog_text="Sair da sala encerra sua participação nesta partida. Continuar?"
    exit_dialog.confirmed.connect(leave_room)
    add_child(exit_dialog)

func start_local():
    game.online=null
    online_mode=false
    game.game_started=true
    game._new_game()
    menu.hide(); hud.hide()

func connect_room(login:Dictionary):
    if endpoint.is_empty():
        menu_info.text="O servidor público ainda não foi publicado. O modo local continua disponível."
        return
    if not endpoint.begins_with("wss://") and not endpoint.begins_with("ws://127.0.0.1:") and not endpoint.begins_with("ws://localhost:"):
        menu_info.text="O endereço do servidor precisa usar uma conexão segura."
        return
    if String(login.get("type",""))=="join" and String(login.get("room","")).length()!=6:
        menu_info.text="Digite os 6 caracteres do código."
        return
    if socket: socket.close()
    online_mode=true; connected=false; joined=false; pending=false
    game.online=self
    greeting=login.duplicate()
    retry_after=0.0; elapsed=0.0
    socket=WebSocketPeer.new()
    var err=socket.connect_to_url(endpoint)
    if err!=OK:
        message="Não foi possível conectar. Tente novamente."
        retry_after=4.0
    else: message="Conectando ao servidor… A hospedagem gratuita pode levar um momento."
    menu_info.text=message

func resume_room():
    if saved.is_empty(): return
    room=String(saved.room); token=String(saved.token)
    connect_room({"type":"resume","room":room,"token":token})

func _process(delta):
    if not online_mode:
        if game.game_started: menu.hide()
        return
    elapsed+=delta
    if retry_after>0:
        retry_after-=delta
        if retry_after<=0:
            if not room.is_empty() and not token.is_empty():
                connect_room({"type":"resume","room":room,"token":token})
            else: connect_room(greeting)
        return
    if not socket: return
    socket.poll()
    var state=socket.get_ready_state()
    if state==WebSocketPeer.STATE_OPEN:
        if not connected:
            connected=true
            socket.send_text(JSON.stringify(greeting))
        while socket.get_available_packet_count()>0:
            var msg=JSON.parse_string(socket.get_packet().get_string_from_utf8())
            if msg is Dictionary: receive(msg)
        ping_at+=delta
        if ping_at>12.0:
            ping_at=0.0
            socket.send_text('{"type":"ping"}')
    elif state==WebSocketPeer.STATE_CLOSED or (state==WebSocketPeer.STATE_CONNECTING and elapsed>90.0):
        if leaving:
            finish_leave()
            return
        connected=false; both_connected=false; pending=false
        game.cancel_drag()
        message="Conexão perdida. Tentando reconectar à mesma sala…"
        hud_info.text=message; menu_info.text=message
        retry_after=4.0
    if pending and elapsed>15.0:
        pending=false
        socket.close()
    refresh_hud()

func receive(msg:Dictionary):
    var type=String(msg.get("type",""))
    if type=="welcome":
        room=String(msg.room); color=String(msg.color); token=String(msg.token)
        saved={"room":room,"token":token}
        var config=ConfigFile.new()
        config.set_value("session","room",room)
        config.set_value("session","token",token)
        config.save("user://online_session.cfg")
        reconnect_button.show()
        joined=true
        menu.hide(); hud.show()
        game.game_started=true
    elif type=="state":
        pending=false
        revision=int(msg.revision)
        started=bool(msg.started)
        both_connected=bool(msg.white_connected) and bool(msg.black_connected)
        game.cancel_drag()
        game.selected=Vector2i(-1,-1); game.legal_moves.clear()
        game.pieces.clear()
        for piece in msg.board:
            game.pieces[Vector2i(int(piece[0]),int(piece[1]))]=String(piece[2])
        game.turn=String(msg.turn)
        game.status=String(msg.status)
        game.game_over=bool(msg.game_over)
        game.promotion_pending=bool(msg.promotion_pending)
        game.promotion_color=String(msg.promotion_color)
        game.promotion_cell=cell(msg.promotion_cell)
        game.last_from=cell(msg.last_from); game.last_to=cell(msg.last_to)
        game.captured_white.assign(msg.captured_white); game.captured_black.assign(msg.captured_black)
        game.move_count=int(msg.move_count)
        message=""
        var votes=msg.restart_votes
        if votes.size()>0:
            message="Você pediu revanche. Aguardando o adversário." if color in votes else "O adversário pediu revanche. Clique em Revanche para aceitar."
        game.queue_redraw()
        if leaving:
            if game.game_over: finish_leave()
            else: send_action("resign")
    elif type=="error":
        pending=false
        message=String(msg.message)
        menu_info.text=message
        if not joined:
            online_mode=false
            game.online=null
            game.game_started=false
            game._new_game()
            if socket: socket.close()
            menu.show(); hud.hide()

func cell(value)->Vector2i:
    return Vector2i(int(value[0]),int(value[1]))

func refresh_hud():
    if not joined: return
    var summary="Sala %s • %s\n"%[room,"Brancas" if color=="w" else "Pretas"]
    if not connected: summary+="Reconectando à mesma partida…"
    elif not started: summary+="Aguardando jogador. Compartilhe o código."
    elif not both_connected: summary+="Adversário desconectado. Partida pausada; aguardando reconexão."
    elif not message.is_empty(): summary+=message
    elif game.game_over: summary+=game.status
    elif pending: summary+="Confirmando jogada…"
    elif game.promotion_pending: summary+="Escolha a promoção." if game.promotion_color==color else "Adversário escolhendo a promoção…"
    else: summary+="Seu turno." if game.turn==color else "Turno do adversário."
    hud_info.text=summary
    restart_button.disabled=not both_connected or not connected

func can_interact()->bool:
    return connected and joined and started and both_connected and not pending and not game.game_over and (game.promotion_color==color if game.promotion_pending else game.turn==color)

func send_action(action:String,data:Dictionary={}):
    if not connected or not joined or pending:
        return
    if action in ["move","promote"] and not can_interact(): return
    if action=="restart" and not both_connected: return
    var payload=data.duplicate()
    payload.type=action; payload.revision=revision
    pending=true; elapsed=0.0
    socket.send_text(JSON.stringify(payload))

func leave_room():
    if connected and joined and not game.game_over:
        leaving=true
        if not pending: send_action("resign")
        return
    finish_leave()

func finish_leave():
    leaving=false
    if socket:
        if connected: socket.send_text('{"type":"leave"}')
        socket.close()
    online_mode=false; connected=false; joined=false
    game.online=null
    game._new_game()
    game.game_started=false
    game.cancel_drag()
    room=""; token=""; saved={}
    var config=ConfigFile.new(); config.save("user://online_session.cfg")
    reconnect_button.hide()
    hud.hide(); menu.show()
    menu_info.text="Escolha como jogar."
    game.queue_redraw()

func open_online_menu():
    menu.show()
    hud.hide()
    menu_info.text="Crie uma sala ou entre com o código de um amigo."

func return_to_main_hub():
    menu.hide()
    var hub=get_parent().get_node_or_null("MainHub")
    if hub: hub.open_home()
