extends SceneTree
# One authoritative instance of the existing game per room. No duplicate chess implementation.
const GAME = preload("res://world.gd")
const MAX_ROOMS = 128
const RECONNECT_SECONDS = 1800
var listener = TCPServer.new()
var peers = {}
var rooms = {}
var next_peer = 0
var cleanup_clock = 0.0

func _initialize():
    var port = int(OS.get_environment("PORT")) if OS.has_environment("PORT") else 8080
    var error = listener.listen(port, "0.0.0.0")
    if error != OK:
        push_error("Cannot listen on port %d: %s" % [port,error_string(error)])
        quit(1)
    print("FRAIHA room server listening on ",port)

func _process(delta):
    while listener.is_connection_available():
        var stream = listener.take_connection()
        if peers.size() >= 512:
            stream.disconnect_from_host()
            continue
        var socket = WebSocketPeer.new()
        socket.inbound_buffer_size = 16384
        socket.max_queued_packets = 32
        if socket.accept_stream(stream) != OK:
            continue
        next_peer += 1
        peers[next_peer] = {"socket":socket,"room":"","color":"","connected_at":Time.get_ticks_msec(),"rate_at":0,"count":0}
    for id in peers.keys():
        if not peers.has(id): continue
        var peer = peers[id]
        var socket = peer.socket
        socket.poll()
        if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
            disconnected(id)
            continue
        if peer.room == "" and Time.get_ticks_msec()-peer.connected_at > 20000:
            socket.close(1000,"Login timeout")
            continue
        while socket.get_available_packet_count() > 0:
            var packet = socket.get_packet()
            if packet.size() > 8192:
                socket.close(1009,"Packet too large")
                break
            var now = int(Time.get_ticks_msec()/1000)
            if peer.rate_at != now:
                peer.rate_at=now; peer.count=0
            peer.count+=1
            if peer.count>20:
                socket.close(1008,"Rate limit")
                break
            var msg=JSON.parse_string(packet.get_string_from_utf8())
            if msg is Dictionary: receive(id,msg)
    cleanup_clock+=delta
    if cleanup_clock>20.0:
        cleanup_clock=0.0
        for code in rooms.keys():
            var room=rooms[code]
            if room.w == 0 and room.b == 0 and Time.get_unix_time_from_system()-room.touched>RECONNECT_SECONDS:
                room.game.queue_free()
                rooms.erase(code)
    return false

func send_to(id:int,msg:Dictionary):
    if peers.has(id):
        var socket=peers[id].socket
        if socket.get_ready_state()==WebSocketPeer.STATE_OPEN:
            socket.send_text(JSON.stringify(msg))

func failure(id:int,message:String):
    send_to(id,{"type":"error","message":message})

func code_for_room()->String:
    const LETTERS="ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    while true:
        var code=""
        for byte in Crypto.new().generate_random_bytes(6): code+=LETTERS[int(byte)%LETTERS.length()]
        if not rooms.has(code): return code
    return ""

func attach(id:int,code:String,color:String):
    var room=rooms[code]
    room[color]=id
    room.touched=Time.get_unix_time_from_system()
    peers[id].room=code; peers[id].color=color
    send_to(id,{"type":"welcome","room":code,"color":color,"token":room.tokens[color]})
    broadcast(code)

func receive(id:int,msg:Dictionary):
    var action=String(msg.get("type",""))
    if action=="ping":
        send_to(id,{"type":"pong"})
        return
    var peer=peers[id]
    if peer.room=="":
        if action=="create":
            if rooms.size()>=MAX_ROOMS:
                failure(id,"Servidor cheio. Tente novamente em alguns minutos.")
                return
            var code=code_for_room()
            var game=GAME.new()
            game.server_mode=true
            root.add_child(game)
            game.game_started=true
            rooms[code]={"game":game,"w":0,"b":0,"started":false,"revision":0,"votes":[],"touched":Time.get_unix_time_from_system(),"tokens":{"w":Crypto.new().generate_random_bytes(24).hex_encode(),"b":Crypto.new().generate_random_bytes(24).hex_encode()}}
            attach(id,code,"w")
        elif action=="join":
            var code=String(msg.get("room","")).strip_edges().to_upper()
            if not rooms.has(code):
                failure(id,"Sala não encontrada ou expirada.")
            elif rooms[code].started:
                failure(id,"Esta sala já tem dois jogadores. Use Reconectar para voltar.")
            else:
                rooms[code].started=true
                attach(id,code,"b")
        elif action=="resume":
            var code=String(msg.get("room",""))
            var token=String(msg.get("token",""))
            if not rooms.has(code):
                failure(id,"A sala expirou ou o servidor reiniciou.")
                return
            var color=""
            for c in ["w","b"]:
                if token==rooms[code].tokens[c]: color=c
            if color=="":
                failure(id,"Não foi possível recuperar esta sessão.")
                return
            if rooms[code][color]!=0:
                failure(id,"Esta sessão ainda está conectada em outra janela.")
                return
            attach(id,code,color)
        else: failure(id,"Crie ou entre em uma sala primeiro.")
        return
    var room=rooms[peer.room]
    var game=room.game
    if action=="leave":
        if room.started and not game.game_over:
            game.game_over=true
            game.status="DESISTÊNCIA — "+("PRETAS VENCEM" if peer.color=="w" else "BRANCAS VENCEM")
            room.revision+=1
        room[peer.color]=0
        peer.room=""
        peer.color=""
        room.touched=Time.get_unix_time_from_system()
        broadcast_room(room)
        return
    if action=="resign":
        if room.started and not game.game_over:
            game.game_over=true
            game.status="DESISTÊNCIA — "+("PRETAS VENCEM" if peer.color=="w" else "BRANCAS VENCEM")
            game.promotion_pending=false
            room.revision+=1
        broadcast(peer.room)
        return
    if not room.started or room.w==0 or room.b==0:
        failure(id,"Aguardando a conexão do outro jogador.")
        return
    if action=="restart":
        if not peer.color in room.votes: room.votes.append(peer.color)
        if room.votes.size()==2:
            game._new_game()
            room.votes=[]
            room.revision+=1
        broadcast(peer.room)
        return
    if int(msg.get("revision",-1))!=room.revision:
        failure(id,"O tabuleiro foi atualizado. Tente a jogada novamente.")
        broadcast(peer.room)
        return
    if game.game_over:
        failure(id,"Partida encerrada.")
        return
    if action=="move":
        if game.promotion_pending or peer.color!=game.turn:
            failure(id,"Aguarde seu turno.")
            return
        var a=msg.get("from",[]); var b=msg.get("to",[])
        if not a is Array or not b is Array or a.size()!=2 or b.size()!=2:
            failure(id,"Jogada inválida.")
            return
        var fr=Vector2i(int(a[0]),int(a[1])); var to=Vector2i(int(b[0]),int(b[1]))
        if not game._inside(fr) or not game._inside(to) or game._color_at(fr)!=peer.color or not to in game._moves(fr):
            failure(id,"Movimento não permitido.")
            return
        game._select(fr)
        var event=InputEventMouseButton.new()
        event.pressed=true; event.button_index=MOUSE_BUTTON_LEFT
        event.position=game.ORIGIN+(Vector2(to)+Vector2.ONE/2)*game.TILE
        game._handle_game_input(event)
    elif action=="promote":
        var kind=String(msg.get("kind",""))
        if not game.promotion_pending or game.promotion_color!=peer.color or not kind in ["Q","R","B","N"]:
            failure(id,"Promoção inválida.")
            return
        game._finish_promotion(kind)
    else:
        failure(id,"Ação desconhecida.")
        return
    room.votes=[]
    room.revision+=1
    room.touched=Time.get_unix_time_from_system()
    broadcast(peer.room)

func state(room:Dictionary)->Dictionary:
    var g=room.game
    var board=[]
    for p in g.pieces: board.append([p.x,p.y,g.pieces[p]])
    return {"type":"state","revision":room.revision,"board":board,"turn":g.turn,"status":g.status,"game_over":g.game_over,"promotion_pending":g.promotion_pending,"promotion_color":g.promotion_color,"promotion_cell":[g.promotion_cell.x,g.promotion_cell.y],"last_from":[g.last_from.x,g.last_from.y],"last_to":[g.last_to.x,g.last_to.y],"captured_white":g.captured_white,"captured_black":g.captured_black,"move_count":g.move_count,"started":room.started,"white_connected":room.w!=0,"black_connected":room.b!=0,"restart_votes":room.votes}

func broadcast(code:String):
    if rooms.has(code): broadcast_room(rooms[code])

func broadcast_room(room:Dictionary):
    var msg=state(room)
    for color in ["w","b"]: send_to(room[color],msg)

func disconnected(id:int):
    if not peers.has(id): return
    var peer=peers[id]
    if rooms.has(peer.room):
        var room=rooms[peer.room]
        if room[peer.color]==id: room[peer.color]=0
        room.votes=[]
        room.touched=Time.get_unix_time_from_system()
        broadcast(peer.room)
    peers.erase(id)
