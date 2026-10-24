extends SceneTree
## Ambiente do servidor (QA/staging × produção): trava da build de produção e online.cfg do repositório.
## A escolha por feature de export ("staging"/"production") é validada nas builds Web reais
## (tools/web_release/ambiente_web.py lê o PCK; o empacotador recusa ambiente trocado).
const Endpoint := preload("res://online_v020/endpoint.gd")
var fails := 0

func check(ok: bool, label: String):
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: fails += 1

func _initialize():
	var prod := "wss://fraiha-xadrez.onrender.com"
	var stg := "wss://fraiha-xadrez-staging.onrender.com"
	check(Endpoint.production_guard(prod, stg, false) == prod, "produção com o servidor oficial passa")
	check(Endpoint.production_guard(stg, stg, false) == "", "produção apontando para staging fica SEM servidor")
	check(Endpoint.production_guard("wss://outro-staging.example", stg, false) == "", "qualquer endereço com 'staging' é recusado em produção")
	check(Endpoint.production_guard("", stg, false) == "", "produção sem servidor continua sem servidor")
	check(Endpoint.production_guard(prod, stg, true) == "", "build marcada como staging E produção fica sem servidor")
	var cfg := ConfigFile.new()
	check(cfg.load("res://online.cfg") == OK, "online.cfg carrega")
	check(String(cfg.get_value("online", "server_url", "")) == prod, "online.cfg [online] = produção oficial")
	check(String(cfg.get_value("staging", "server_url", "")) == stg, "online.cfg [staging] = servidor de testes")
	# R181 · sem feature de ambiente (este teste = build local/de teste): NUNCA o servidor de produção
	if not OS.has_environment("FRAIHA_SERVER_URL"):
		check(Endpoint.server_url() == "", "sem feature de ambiente: sem servidor (produção bloqueada por padrão)")
	check(Endpoint.non_production_guard(prod, prod, false) == "", "build de teste apontando para produção: bloqueado")
	check(Endpoint.non_production_guard(prod + "/", prod, false) == "", "…mesmo com barra no fim")
	check(Endpoint.non_production_guard(prod, prod, true) == prod, "FRAIHA_ALLOW_PRODUCTION=1: liberado (ação consciente)")
	check(Endpoint.non_production_guard(stg, prod, false) == stg, "build de teste com staging: ok")
	check(Endpoint.non_production_guard("ws://127.0.0.1:8799", prod, false) == "ws://127.0.0.1:8799", "servidor local: ok")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	for sec in presets.get_sections():
		if sec.ends_with(".options") or not presets.has_section_key(sec, "name"): continue
		var nm := String(presets.get_value(sec, "name"))
		var feats := String(presets.get_value(sec, "custom_features", ""))
		if nm == "Web Producao": check(feats.contains("production"), "preset oficial '%s' marcado como produção" % nm)
		elif nm == "Windows Desktop": check(feats.contains("staging") and not feats.contains("production"), "R184 · executável do PC usa o MESMO servidor do site (staging)")
		else: check(not feats.contains("production"), "preset '%s' NÃO é produção" % nm)
	check(Endpoint.channel() == "dev", "canal sem feature = dev")
	print("RESULT ", "OK" if fails == 0 else "FALHAS=%d" % fails)
	quit(1 if fails else 0)
