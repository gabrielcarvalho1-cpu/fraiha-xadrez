extends SceneTree
## R184e · pré-move de RECAPTURA (como no chess.com): a casa da própria peça e casas atrás de peças entram.
var fails := 0
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func _initialize():
	var w = load("res://world.gd").new()
	w.pieces = {Vector2i(3, 4): "wN", Vector2i(4, 5): "wP", Vector2i(3, 7): "wQ", Vector2i(3, 6): "wP", Vector2i(2, 3): "bP"}
	var t: Array = w._premove_targets(Vector2i(4, 5))
	check(Vector2i(3, 4) in t, "peão: recaptura na casa do próprio cavalo (d5)")
	check(Vector2i(5, 4) in t, "peão: diagonal vazia também (o adversário pode chegar lá)")
	var q: Array = w._premove_targets(Vector2i(3, 7))
	check(Vector2i(3, 6) in q, "dama: casa do próprio peão à frente")
	check(Vector2i(3, 4) in q and Vector2i(3, 0) in q, "dama: raio passa por cima das peças (podem sair do caminho)")
	check(not (Vector2i(3, 7) in q), "nunca a própria casa de origem")
	var n: Array = w._premove_targets(Vector2i(3, 4))
	check(Vector2i(2, 2) in n and Vector2i(4, 2) in n, "cavalo: saltos normais")
	w.free()
	print("R184_PREMOVE FAILS=%d" % fails)
	quit(1 if fails > 0 else 0)
