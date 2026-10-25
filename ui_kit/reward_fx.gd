extends Control
## R184e · efeitos das telas de conquista do celular (primeiro rival, vitória contra o bot):
## raios de luz dourada girando atrás de um ponto, brilho pulsando e faíscas subindo. Só desenho (sem textura),
## barato no celular: ~30 polígonos por quadro. Não recebe toque.

var center := Vector2.ZERO        # centro dos raios (coordenadas deste Control)
var radius := 300.0
var rays := 14
var ray_color := Color(1.0, 0.82, 0.38, 0.16)
var glow_color := Color(1.0, 0.78, 0.30, 0.30)
var sparkle_area := Rect2()       # vazio = não solta faíscas
var sparkles := 26
var t := 0.0
var _sp: Array = []

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func _process(delta: float):
	t += delta
	if sparkle_area.size.x > 0.0:
		if _sp.is_empty():
			for i in sparkles: _sp.append(_new_sparkle(true))
		for s in _sp:
			s.p += s.v * delta
			s.life -= delta
			if s.life <= 0.0 or not sparkle_area.grow(40).has_point(s.p):
				var n := _new_sparkle(false)
				s.p = n.p; s.v = n.v; s.life = n.life; s.max = n.max; s.r = n.r
	queue_redraw()

func _new_sparkle(anywhere: bool) -> Dictionary:
	var a := sparkle_area
	var p := Vector2(randf_range(a.position.x, a.end.x), randf_range(a.position.y, a.end.y) if anywhere else a.end.y)
	var life := randf_range(1.6, 3.4)
	return {"p": p, "v": Vector2(randf_range(-14, 14), randf_range(-70, -30)), "life": life, "max": life, "r": randf_range(1.6, 3.6)}

func _draw():
	if radius > 0.0 and rays > 0:
		var rot := t * 0.35
		var half := PI / float(rays) * 0.42
		for i in rays:
			var a := rot + TAU * float(i) / float(rays)
			var p1 := center + Vector2(cos(a - half), sin(a - half)) * radius
			var p2 := center + Vector2(cos(a + half), sin(a + half)) * radius
			draw_polygon(PackedVector2Array([center, p1, p2]), PackedColorArray([ray_color, Color(ray_color, 0.0), Color(ray_color, 0.0)]))
		var pulse := 0.75 + 0.25 * sin(t * 2.4)
		for k in 4:
			var rr := radius * (0.18 + 0.12 * k) * pulse
			draw_circle(center, rr, Color(glow_color, glow_color.a * (0.55 - 0.12 * k)))
	for s in _sp:
		var f: float = clampf(s.life / s.max, 0.0, 1.0)
		var al: float = sin(f * PI)
		draw_circle(s.p, s.r * 2.4, Color(1.0, 0.85, 0.45, 0.18 * al))
		draw_circle(s.p, s.r, Color(1.0, 0.95, 0.75, 0.85 * al))
