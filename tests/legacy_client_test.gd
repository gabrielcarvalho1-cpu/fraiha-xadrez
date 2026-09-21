extends SceneTree
var world
var failures = 0
func verify(ok: bool, message: String):
    if not ok:
        failures += 1
        push_error(message)
    else: print("PASS: " + message)
func click_cell(x:int,y:int):
    var e=InputEventMouseButton.new()
    e.button_index=MOUSE_BUTTON_LEFT
    e.pressed=true
    e.position=world.ORIGIN+Vector2(x+0.5,y+0.5)*world.TILE
    world._unhandled_input(e)
func move_piece(a:Vector2i,b:Vector2i):
    click_cell(a.x,a.y)
    click_cell(b.x,b.y)
func _initialize():
    call_deferred("run")
func run():
    world=load("res://world.tscn").instantiate()
    root.add_child(world)
    await process_frame
    world.game_started=true
    verify(world.pieces.size()==32,"32 starting pieces")
    verify(world._moves(Vector2i(4,6)).size()==2,"pawn legal opening moves")
    click_cell(0,1)
    verify(world.selected==Vector2i(-1,-1),"wrong turn cannot select")
    move_piece(Vector2i(4,6),Vector2i(4,4))
    verify(world.turn=="b" and world.pieces.has(Vector2i(4,4)),"input mapping and turn")
    move_piece(Vector2i(3,1),Vector2i(3,3))
    move_piece(Vector2i(4,4),Vector2i(3,3))
    verify(world.pieces.size()==31 and world.captured_black.size()==1,"capture")
    world._new_game()
    move_piece(Vector2i(5,6),Vector2i(5,5))
    move_piece(Vector2i(4,1),Vector2i(4,3))
    move_piece(Vector2i(6,6),Vector2i(6,4))
    move_piece(Vector2i(3,0),Vector2i(7,4))
    verify(world.game_over and world._in_check("w") and "XEQUE-MATE" in world.status,"Fool's mate")
    world._new_game()
    world.pieces={Vector2i(4,7):"wK",Vector2i(4,0):"bR",Vector2i(0,0):"bK",Vector2i(4,6):"wR"}
    verify(not Vector2i(3,6) in world._moves(Vector2i(4,6)),"pinned rook cannot expose king")
    world.pieces={Vector2i(4,7):"wK",Vector2i(7,0):"bK",Vector2i(0,1):"wP"}
    move_piece(Vector2i(0,1),Vector2i(0,0))
    verify(world.promotion_pending,"promotion waits for choice")
    world._finish_promotion("N")
    verify(world.pieces[Vector2i(0,0)]=="wN" and not world.promotion_pending,"promotion selection")
    world._new_game()
    verify(world.pieces.size()==32 and world.turn=="w" and not world.game_over,"restart resets game")
    world.queue_free()
    await process_frame
    var stage=load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    verify(stage.has_node("World") and stage.has_node("Online"), "current game and online scene loads")
    stage.queue_free()
    await process_frame
    print("LEGACY_FAILURES=", failures)
    quit(failures)
