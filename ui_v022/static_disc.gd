extends Node2D
## R52e · Disco desenhado UMA vez (draw_circle) e animado só por position / scale / modulate.
## Motivo: na Web (GL Compatibility), cada draw_circle vira um polígono com buffers próprios; redesenhar
## círculos todo quadro criava e apagava ~100 buffers de GPU por quadro, e o runtime (Emscripten) guarda
## um id novo para cada um numa tabela que só cresce — memória subindo com a Home parada.
## Mover/escalar/esmaecer um nó NÃO redesenha: a geometria fica a mesma e nenhum buffer é recriado.
## Uso: cor com alfa 1 + modulate.a = alfa do quadro; raio do quadro = radius * scale.
var radius := 1.0
var color := Color.WHITE

func _init(r: float = 1.0, c: Color = Color.WHITE):
    radius = r
    color = c

func _draw():
    draw_circle(Vector2.ZERO, radius, color)
