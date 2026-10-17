extends CanvasLayer
## R115 · CARREGAMENTO MAIS RÁPIDO (Web). A build Web sai em DOIS pacotes:
##   • principal (index-p….pck): Home, xadrez, contas, Premium, Madeira — o que precisa para abrir e jogar;
##   • CONTEÚDO EXTRA (outro index-p….pck): XEQUE e MARCHA (artes e sons), cenários/peças das ligas
##     Bronze → Challenger e músicas das ligas.
## O index.html diz qual é o pacote extra (<meta name="fraiha-conteudo" content="index-p….pck" data-size="N">).
## Ele é baixado sozinho, em segundo plano, alguns segundos depois da Home aparecer, e fica guardado no
## aparelho (user://conteudo): na próxima visita carrega na hora, sem rede. Quem abre XEQUE/MARCHA antes de
## terminar vê "Preparando o modo… N%" e entra assim que chega. Os temas das ligas caem em Madeira até lá e
## voltam sozinhos quando o pacote chega.
## Fora da Web dividida (PC, editor, testes, build antiga sem a meta), tudo já está no pacote principal:
## pronto = true desde o início e nada muda.
signal finished(ok: bool)

const DIR := "user://conteudo"
const START_DELAY := 2.5
const TRIES := 3
const GOLD := Color("f4ce7f")
const CREAM := Color("efe3c4")
const FONT := preload("res://account/fonts/Cinzel-Bold.woff")

static var instance = null
static var pronto := true

var pck_name := ""
var pck_size := 0
var http: HTTPRequest
var busy := false
var tries := 0
var error := ""
var _wait: Control
var _wait_label: Label
var _wait_bar: ProgressBar
var _wait_title := ""

func _init():
	name = "ConteudoExtra"
	layer = 125
	instance = self

func _ready():
	if not OS.has_feature("web"): return
	var info = JavaScriptBridge.eval("(function(){var m=document.querySelector('meta[name=\"fraiha-conteudo\"]');return m?(m.content+'|'+(m.getAttribute('data-size')||'0')):''})()")
	if not (info is String) or String(info).is_empty(): return
	var parts := String(info).split("|")
	if parts.size() != 2 or not parts[0].begins_with("index-p") or not parts[0].ends_with(".pck"): return
	pck_name = parts[0]
	pck_size = int(parts[1])
	pronto = false
	if _try_cached(): return
	get_tree().create_timer(START_DELAY).timeout.connect(start)

static func is_ready() -> bool:
	return pronto

func _path() -> String:
	return DIR + "/" + pck_name

func _try_cached() -> bool:
	if not FileAccess.file_exists(_path()): return false
	var f := FileAccess.open(_path(), FileAccess.READ)
	var ok := f != null and (pck_size <= 0 or f.get_length() == pck_size)
	if f != null: f.close()
	if not ok:
		DirAccess.remove_absolute(_path())
		return false
	return _mount()

func _mount() -> bool:
	# replace_files = false: o pacote extra também traz project.binary / cache de UIDs / splash (o exportador
	# sempre põe); os do pacote principal continuam valendo
	if not ProjectSettings.load_resource_pack(_path(), false):
		DirAccess.remove_absolute(_path())
		print("[conteudo] falhou ao abrir ", pck_name)
		return false
	pronto = true
	print("[conteudo] pronto: ", pck_name)
	_cleanup_old()
	finished.emit(true)
	return true

func _cleanup_old():
	var d := DirAccess.open(DIR)
	if d == null: return
	for f in d.get_files():
		if f != pck_name: d.remove(f)

## Começa (ou continua) a baixar o pacote extra. Sem efeito se já está pronto ou baixando.
func start():
	if pronto or busy or pck_name.is_empty(): return
	busy = true
	tries += 1
	error = ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var base = JavaScriptBridge.eval("location.href.split('#')[0].split('?')[0].replace(/[^\\/]*$/, '')")
	if http == null:
		http = HTTPRequest.new()
		http.name = "ConteudoHTTP"
		http.download_chunk_size = 1048576
		http.timeout = 0
		add_child(http)
		http.request_completed.connect(_on_done)
	http.download_file = _path() + ".baixando"
	print("[conteudo] baixando ", pck_name, " (tentativa ", tries, ")")
	if http.request(String(base) + pck_name) != OK: _on_done(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func _on_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray):
	busy = false
	var tmp := _path() + ".baixando"
	var got := 0
	if FileAccess.file_exists(tmp):
		var f := FileAccess.open(tmp, FileAccess.READ)
		if f != null:
			got = f.get_length()
			f.close()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and (pck_size <= 0 or got == pck_size):
		DirAccess.remove_absolute(_path())
		DirAccess.rename_absolute(tmp, _path())
		if _mount(): return
	DirAccess.remove_absolute(tmp)
	error = "rede (%d/%d)" % [result, code]
	print("[conteudo] falhou: ", error, " · ", got, " de ", pck_size, " bytes")
	if tries < TRIES:
		get_tree().create_timer(2.0 * tries).timeout.connect(start)
	else:
		finished.emit(false)

func progress() -> float:
	if pronto: return 1.0
	if http == null or pck_size <= 0: return 0.0
	return clampf(float(http.get_downloaded_bytes()) / float(pck_size), 0.0, 1.0)

## Garante o conteúdo extra antes de abrir um modo. Mostra "Preparando…" com a porcentagem enquanto baixa.
## Devolve true quando pronto; false se não deu (sem internet) — quem chamou não abre o modo.
static func ensure(what: String) -> bool:
	if pronto or instance == null: return true
	return await instance._ensure(what)

func _ensure(what: String) -> bool:
	if tries >= TRIES and not busy:
		tries = 0
	if not busy: start()
	_show_wait(what)
	var ok: bool = await finished
	_hide_wait()
	if not ok:
		var hub = get_tree().root.find_child("MainHub", true, false)
		if hub != null and hub.has_method("show_notice"):
			hub.show_notice("SEM CONEXÃO", "Não foi possível baixar o %s agora. Confira a internet e tente de novo." % what)
	return ok

func _show_wait(what: String):
	_wait_title = what
	if _wait == null:
		_wait = Control.new()
		_wait.name = "ConteudoEspera"
		_wait.set_anchors_preset(Control.PRESET_FULL_RECT)
		_wait.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_wait)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.6)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_wait.add_child(shade)
		var box := PanelContainer.new()
		box.name = "Caixa"
		var st := StyleBoxTexture.new()
		st.texture = preload("res://ui_kit/art/fr_btn_azul.png")
		for side in ["left", "right", "top", "bottom"]: st.set("texture_margin_" + side, 18.0)
		for side in ["left", "right"]: st.set("content_margin_" + side, 34.0)
		for side in ["top", "bottom"]: st.set("content_margin_" + side, 22.0)
		box.add_theme_stylebox_override("panel", st)
		_wait.add_child(box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		box.add_child(v)
		_wait_label = Label.new()
		_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wait_label.add_theme_font_override("font", FONT)
		_wait_label.add_theme_font_size_override("font_size", 22)
		_wait_label.add_theme_color_override("font_color", GOLD)
		_wait_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
		_wait_label.add_theme_constant_override("outline_size", 4)
		v.add_child(_wait_label)
		_wait_bar = ProgressBar.new()
		_wait_bar.show_percentage = false
		_wait_bar.custom_minimum_size = Vector2(280, 12)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		bg.border_color = Color("6b5428")
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("e2b24f")
		fill.set_corner_radius_all(4)
		_wait_bar.add_theme_stylebox_override("background", bg)
		_wait_bar.add_theme_stylebox_override("fill", fill)
		v.add_child(_wait_bar)
		var sub := Label.new()
		sub.text = "Só na primeira vez: depois abre na hora."
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_override("font", FONT)
		sub.add_theme_font_size_override("font_size", 14)
		sub.add_theme_color_override("font_color", CREAM)
		v.add_child(sub)
	_wait.visible = true
	_update_wait()

func _hide_wait():
	if _wait != null: _wait.visible = false

func _update_wait():
	if _wait == null or not _wait.visible: return
	var p := progress()
	_wait_label.text = "PREPARANDO O %s… %d%%" % [_wait_title, int(round(p * 100.0))]
	_wait_bar.max_value = 1.0
	_wait_bar.value = p
	var box: Control = _wait.get_node("Caixa")
	box.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var sz := box.get_combined_minimum_size()
	box.size = sz
	# R149 · celular em pé: a caixa não cabia na largura (cortava nas laterais) → encolhe para caber com margem
	var k: float = minf(1.0, minf((vs.x - 32.0) / maxf(1.0, sz.x), (vs.y - 32.0) / maxf(1.0, sz.y)))
	box.scale = Vector2(k, k)
	box.position = ((vs - sz * k) * 0.5).floor()

var _log_t := 0.0
func _process(d):
	if _wait != null and _wait.visible: _update_wait()
	if busy and http != null:
		_log_t += d
		if _log_t >= 5.0:
			_log_t = 0.0
			print("[conteudo] ", http.get_downloaded_bytes(), " de ", pck_size, " bytes · status ", http.get_http_client_status())
