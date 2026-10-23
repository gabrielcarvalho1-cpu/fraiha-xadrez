extends CanvasLayer
## R176.9 · CONTAGEM antes de começar a partida de XEQUE e de MARCHA REAL: 3 → 2 → 1 → VAI COMEÇAR (artes do dono,
## ui_kit/countdown/). Cobre a tela (escurece o fundo e segura o toque); a partida só anda depois que ela termina.
## Uso: Countdown.play(parent) → Node com .running; quem chama segura a própria partida enquanto running == true.
## Nos testes automáticos (SceneTree com script) não aparece, a menos que FRAIHA_COUNTDOWN=1.
signal finished

const ART := {
	"3": preload("res://ui_kit/countdown/n3.png"),
	"2": preload("res://ui_kit/countdown/n2.png"),
	"1": preload("res://ui_kit/countdown/n1.png"),
	"go": preload("res://ui_kit/countdown/vai_comecar.png"),
}
const STEP := 0.85        # cada número
const GO := 1.15          # VAI COMEÇAR
const TOTAL := STEP * 3.0 + GO
const SEQ := ["3", "2", "1", "go"]

const STEP_SFX := preload("res://audio_v025/padrao/movimento.mp3")   # som do peão andando (VAI COMEÇAR: o mesmo, até chegar o áudio próprio)
var running := false
var stage = null
var _last := -1
var t := 0.0
var shade: ColorRect
var pic: TextureRect

## Liga a contagem por cima de `parent`. Devolve o nó (ou null quando desligada nos testes).
static func play(parent: Node, p_stage = null) -> Node:
	if not enabled(parent): return null
	var c = load("res://ui_kit/countdown.gd").new()
	c.stage = p_stage
	parent.add_child(c)
	return c

static func enabled(n: Node) -> bool:
	var env := OS.get_environment("FRAIHA_COUNTDOWN")
	if env == "0": return false
	if env == "1": return true
	var ml = Engine.get_main_loop()
	return not (ml != null and ml.get_script() != null)   # teste automático (-s script): sem contagem

func _ready():
	layer = 112
	name = "MatchCountdown"
	shade = ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP   # a partida não recebe toque durante a contagem
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	pic = TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pic)
	running = true
	_show(0.0)

func _process(delta):
	if not running: return
	t += delta
	if t >= TOTAL:
		running = false
		finished.emit()
		queue_free()
		return
	_show(t)

func _show(tt: float):
	var idx := mini(3, int(tt / STEP))
	var local := tt - idx * STEP
	var dur := STEP if idx < 3 else GO
	var key: String = SEQ[idx]
	pic.texture = ART[key]
	if idx != _last:
		_last = idx
		if stage != null: preload("res://ui_v022/mode_sound.gd").play(stage, STEP_SFX, -2.0 if key == "go" else -5.0, 0.9 if key == "go" else 1.0)
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	var box := Vector2(vs.x * (0.86 if portrait else 0.5), vs.y * (0.42 if portrait else 0.56))
	if key == "go": box = Vector2(vs.x * (0.94 if portrait else 0.62), vs.y * (0.48 if portrait else 0.62))
	# entra com um "pulo" (grande → normal), segura e sai encolhendo e sumindo
	var a_in := clampf(local / 0.14, 0.0, 1.0)
	var a_out := clampf((dur - local) / 0.18, 0.0, 1.0)
	var sc := 1.0 + 0.32 * pow(1.0 - a_in, 2.0) - 0.08 * (1.0 - a_out)
	pic.size = box * sc
	pic.position = (vs - pic.size) / 2.0
	pic.modulate.a = minf(a_in, a_out)
	# fundo: escurece no começo e clareia no fim do VAI COMEÇAR
	var fade_in := clampf(tt / 0.25, 0.0, 1.0)
	var fade_out := clampf((TOTAL - tt) / 0.35, 0.0, 1.0)
	shade.color.a = 0.55 * minf(fade_in, fade_out)
