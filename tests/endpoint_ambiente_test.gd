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
	# sem feature de ambiente (este teste): servidor = [online], canal "dev"
	if not OS.has_environment("FRAIHA_SERVER_URL"):
		check(Endpoint.server_url() == prod, "sem feature de ambiente usa [online]")
	check(Endpoint.channel() == "dev", "canal sem feature = dev")
	print("RESULT ", "OK" if fails == 0 else "FALHAS=%d" % fails)
	quit(1 if fails else 0)
