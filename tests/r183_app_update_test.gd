extends SceneTree
## R183 · aviso de atualização do app: decisão (em dia / opcional / obrigatória) e APP_CODE igual ao preset.
const AppUpdate = preload("res://ui_v022/app_update.gd")
var failures := 0
func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _initialize():
	var u := "https://jogar.fraihaxadrez.com/app/FRAIHA-Xadrez.apk"
	check(AppUpdate.decide(2, {"latest": 2, "min": 1, "url": u}) == "", "em dia: nada")
	check(AppUpdate.decide(2, {"latest": 3, "min": 1, "url": u}) == "optional", "versão nova: aviso com Depois")
	check(AppUpdate.decide(2, {"latest": 4, "min": 3, "url": u}) == "required", "abaixo do mínimo: obrigatória")
	check(AppUpdate.decide(1, {"latest": 3, "min": 1, "url": "http://x"}) == "", "link sem https: ignora")
	check(AppUpdate.http_base("wss://fraiha-xadrez-staging.onrender.com") == "https://fraiha-xadrez-staging.onrender.com", "base https do servidor")
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	var code := -1
	for s in cfg.get_sections():
		if not s.ends_with(".options") and String(cfg.get_value(s, "platform", "")) == "Android":
			code = int(cfg.get_value(s + ".options", "version/code", -1))
	check(code == AppUpdate.APP_CODE, "APP_CODE (%d) = version/code do preset Android (%d)" % [AppUpdate.APP_CODE, code])
	print("R183_APP_UPDATE FAILS=%d" % failures)
	quit(1 if failures > 0 else 0)
