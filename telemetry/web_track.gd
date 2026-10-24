extends RefCounted
## R181 · ponte Godot → web/telemetry/fraiha-track.js (window.__fraihaT). Só Web; fora da Web não faz nada.
## O script do site junta os eventos e manda para o servidor (POST /t), MESMO SEM LOGIN.
## Só nomes de tela/botão, tempos, modo/resultado de partida e códigos de erro. NUNCA texto digitado.

static func push(ev: Dictionary) -> void:
	if not OS.has_feature("web"): return
	JavaScriptBridge.eval("try{window.__fraihaT&&window.__fraihaT.push(" + JSON.stringify(ev) + ")}catch(e){}", true)

static func screen(label: String) -> void:
	push({"k": "screen", "n": label})

static func click(label: String, node_id: String, screen_label: String) -> void:
	push({"k": "click", "n": label, "id": node_id, "s": screen_label})

## login: método guest/email/google/signup; resultado start/ok/error; code = código curto do erro
static func login(method: String, result: String, code := "") -> void:
	push({"k": "login", "n": method, "r": result, "c": code.left(60)})

## partida: modo bot/local/online/ranked/casual/xeque/marcha; bot = id do bot (madeira…); result win/loss/draw
static func match_start(mode: String, bot := "") -> void:
	push({"k": "match", "n": "start", "m": mode, "b": bot})
	pixel("PrimeiraPartida", {"modo": mode})

static func match_end(mode: String, result: String, bot := "") -> void:
	push({"k": "match", "n": "end", "m": mode, "r": result, "b": bot})
	pixel("PartidaConcluida", {"modo": mode, "resultado": result})

## jogo carregou (fim do carregamento): tempo desde que a página abriu
static func loaded() -> void:
	if not OS.has_feature("web"): return
	JavaScriptBridge.eval("try{window.__fraihaT&&window.__fraihaT.done()}catch(e){}", true)

## evento de conversão (pixel do navegador + Conversions API no servidor, mesmo event_id; 1x por visita)
static func pixel(name: String, params := {}, standard := false) -> void:
	if not OS.has_feature("web"): return
	JavaScriptBridge.eval("try{window.__fraihaT&&window.__fraihaT.px(" + JSON.stringify(name) + "," + JSON.stringify(params) + "," + ("true" if standard else "false") + ")}catch(e){}", true)

## sid/vid desta aba (para ligar a conexão do jogo à visita): "" fora da Web ou sem o script
static func ids() -> Dictionary:
	if not OS.has_feature("web"): return {}
	var s = JavaScriptBridge.eval("(window.__fraihaT&&window.__fraihaT.sid)||''", true)
	var v = JavaScriptBridge.eval("(window.__fraihaT&&window.__fraihaT.vid)||''", true)
	if s == null or String(s).is_empty(): return {}
	return {"sid": String(s), "vid": String(v)}
