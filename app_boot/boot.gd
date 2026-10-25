extends Control
## R185 · APP ANDROID: atualização SEM baixar o APK de novo.
## O app abre nesta cena (run/main_scene.android) antes do jogo. Ela:
##   1. lê o manifesto https://jogar.fraihaxadrez.com/app/patch-android.json
##        {"base": <versionCode do APK>, "id": "<nome do pacote>", "url": "https://…pck", "size": N, "sha256": "…"}
##   2. se há pacote novo para ESTE APK (base == BASE_CODE) e ele ainda não foi baixado: baixa (só o que mudou,
##      gerado com godot --export-patch), confere o SHA-256 e guarda em user://patch/;
##   3. carrega o pacote por cima do jogo (ProjectSettings.load_resource_pack, substitui os arquivos) e abre o jogo.
## Sem internet / manifesto fora do ar / pacote corrompido: abre o jogo com o último pacote bom (ou sem nenhum).
## Mudanças "nativas" (voz, permissões, ícone, versão do Godot, classes novas com class_name) ainda pedem APK novo.
## Teste no emulador: adb pode criar user://patch/manifest_url.txt com outro endereço de manifesto.

const BASE_CODE := 5          # versionCode do APK que traz este arquivo (= export_presets Android version/code)
const MANIFEST_URL := "https://jogar.fraihaxadrez.com/app/patch-android.json"
const MAIN := "res://presentation_v019/stage.tscn"
const DIR := "user://patch"
const PACK := "user://patch/patch.pck"
const CFG := "user://patch/patch.cfg"
const SPLASH := preload("res://branding/android/splash_portrait_tall.png")

var _http: HTTPRequest
var _label: Label
var _bar: ProgressBar
var _manifest := {}
var _dl_started := 0
var _done := false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.015)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var art := TextureRect.new()
	art.texture = SPLASH
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color("f4ead2"))
	_label.add_theme_color_override("font_outline_color", Color("1a0f04"))
	_label.add_theme_constant_override("outline_size", 6)
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -120
	_label.offset_bottom = -80
	add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.visible = false
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_left = 60
	_bar.offset_right = -60
	_bar.offset_top = -70
	_bar.offset_bottom = -56
	add_child(_bar)
	DirAccess.make_dir_recursive_absolute(DIR)
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_manifest)
	var err := _http.request(_manifest_url() + "?t=%d" % Time.get_unix_time_from_system())
	if err != OK: _finish()
	# nunca segura o jogador: no máximo 8 s esperando o manifesto
	get_tree().create_timer(9.0).timeout.connect(func(): if _dl_started == 0: _finish())

func _manifest_url() -> String:
	var f := FileAccess.open(DIR + "/manifest_url.txt", FileAccess.READ)
	if f != null:
		var u := f.get_as_text().strip_edges()
		if u.begins_with("https://"): return u
	return MANIFEST_URL

static func installed() -> Dictionary:
	var c := ConfigFile.new()
	if c.load(CFG) != OK: return {}
	return {"base": int(c.get_value("patch", "base", 0)), "id": String(c.get_value("patch", "id", "")), "sha256": String(c.get_value("patch", "sha256", ""))}

func _on_manifest(result: int, code: int, _h, body: PackedByteArray):
	if _done: return true
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return _finish()
	var m = JSON.parse_string(body.get_string_from_utf8())
	if not m is Dictionary: return _finish()
	_manifest = m
	var have := installed()
	var id := String(m.get("id", ""))
	if int(m.get("base", 0)) != BASE_CODE: return _finish()
	if id.is_empty():
		_clear()   # sem pacote para este APK (ex.: depois de um APK novo): roda o jogo puro
		return _finish()
	if have.get("id", "") == id and have.get("base", 0) == BASE_CODE and FileAccess.file_exists(PACK): return _finish()
	var url := String(m.get("url", ""))
	if not url.begins_with("https://") or String(m.get("sha256", "")).length() != 64: return _finish()
	_dl_started = Time.get_ticks_msec()
	_label.text = "Atualizando o jogo…"
	_bar.visible = true
	_bar.value = 0
	_http.request_completed.disconnect(_on_manifest)
	_http.request_completed.connect(_on_pack)
	_http.download_file = DIR + "/download.pck"
	_http.timeout = clampf(float(m.get("size", 0)) / 150000.0, 30.0, 180.0)   # internet lenta: até 3 min
	if _http.request(url) != OK: _finish()

func _process(_d):
	if _dl_started > 0 and not _done and _http != null:
		var total := maxi(1, int(_manifest.get("size", _http.get_body_size())))
		_bar.value = 100.0 * float(_http.get_downloaded_bytes()) / float(total)

func _on_pack(result: int, code: int, _h, _b):
	if _done: return
	var tmp := DIR + "/download.pck"
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.get_sha256(tmp) == String(_manifest.get("sha256", "")).to_lower():
		DirAccess.remove_absolute(PACK)
		DirAccess.rename_absolute(tmp, PACK)
		var c := ConfigFile.new()
		c.set_value("patch", "base", BASE_CODE)
		c.set_value("patch", "id", String(_manifest.get("id", "")))
		c.set_value("patch", "sha256", String(_manifest.get("sha256", "")).to_lower())
		c.save(CFG)
	else:
		DirAccess.remove_absolute(tmp)   # incompleto ou corrompido: fica com o pacote anterior
	_finish()

func _clear():
	DirAccess.remove_absolute(PACK)
	DirAccess.remove_absolute(CFG)

func _finish() -> bool:
	if _done: return true
	_done = true
	if _http != null: _http.cancel_request()
	var have := installed()
	if have.get("base", 0) == BASE_CODE and FileAccess.file_exists(PACK):
		if FileAccess.get_sha256(PACK) == have.get("sha256", "") and ProjectSettings.load_resource_pack(PACK, true):
			print("[patch] aplicado: ", have.get("id", ""))
		else:
			_clear()
	elif FileAccess.file_exists(PACK):
		_clear()   # pacote de outro APK (o app foi atualizado por inteiro): descarta
	get_tree().change_scene_to_file.call_deferred(MAIN)
	return true
