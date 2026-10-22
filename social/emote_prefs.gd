extends RefCounted
## R176 · Liga/desliga os EMOTES (os balões que aparecem ao lado da foto do jogador). Guardado no aparelho.
## Desligado: nenhum balão aparece (nem os seus nem os do adversário); a frase continua discreta no chat.
## Muda em CONFIGURAÇÕES (tela inicial) e nas opções da partida (PC: engrenagem · celular: AÇÕES).

const PATH := "user://emotes.cfg"
static var _loaded := false
static var _on := true

static func enabled() -> bool:
	if not _loaded:
		_loaded = true
		var cf := ConfigFile.new()
		if cf.load(PATH) == OK: _on = bool(cf.get_value("emotes", "enabled", true))
	return _on

static func set_enabled(v: bool) -> void:
	_loaded = true
	_on = v
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("emotes", "enabled", v)
	cf.save(PATH)

static func toggle() -> bool:
	set_enabled(not enabled())
	return _on

## Ícone dos emotes (balão de fala com um sorriso), desenhado ao vivo no quadrado r.
static func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var s := minf(r.size.x, r.size.y)
	var c := r.get_center() + Vector2(0, -s * 0.04)
	var rad := s * 0.36
	var w := maxf(1.5, s * 0.075)
	ci.draw_arc(c, rad, deg_to_rad(125), deg_to_rad(125 + 330), 28, col, w, true)
	# rabinho do balão (embaixo, à esquerda)
	var a := c + Vector2(cos(deg_to_rad(118)), sin(deg_to_rad(118))) * rad
	var b := c + Vector2(cos(deg_to_rad(140)), sin(deg_to_rad(140))) * rad
	var tip := c + Vector2(-rad * 0.95, rad * 1.12)
	ci.draw_colored_polygon(PackedVector2Array([a, b, tip]), col)
	# rosto: olhos + sorriso
	ci.draw_circle(c + Vector2(-rad * 0.36, -rad * 0.2), maxf(1.2, s * 0.055), col)
	ci.draw_circle(c + Vector2(rad * 0.36, -rad * 0.2), maxf(1.2, s * 0.055), col)
	ci.draw_arc(c + Vector2(0, rad * 0.02), rad * 0.5, deg_to_rad(25), deg_to_rad(155), 14, col, w, true)
