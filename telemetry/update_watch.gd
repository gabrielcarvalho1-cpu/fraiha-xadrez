extends Node
## R180 · AVISO DE ATUALIZAÇÃO. No site (Web), de tempos em tempos o jogo baixa o index.html publicado (sem cache) e
## compara o pacote que ele aponta ("mainPack": index-p<sha>.pck) com o pacote que está rodando agora. Se mudou,
## saiu versão nova: quando o jogador estiver no LOBBY (nunca no meio de partida/mesa), aparece a janela
## "NOVA ATUALIZAÇÃO · ATUALIZAR AGORA". DEPOIS adia: volta a perguntar ao sair da próxima partida ou em 10 min.

const CHECK_EVERY := 60.0   # R198 · era 180 s: o dono quer ver o aviso logo depois de publicar
const SNOOZE := 600.0
const JS_SETUP := """
(function(){
  var U = window.__fraihaUpd = window.__fraihaUpd || { cur: '', got: '', busy: false, at: 0 };
  try { if (!U.cur && typeof GODOT_CONFIG !== 'undefined' && GODOT_CONFIG.mainPack) U.cur = String(GODOT_CONFIG.mainPack); } catch (e) {}
  return U.cur;
})()
"""
const JS_CHECK := """
(function(){
  var U = window.__fraihaUpd; if (!U || !U.cur || U.busy) return 0;
  U.busy = true;
  fetch(location.pathname + '?upd=' + Date.now(), { cache: 'no-store', credentials: 'omit' })
    .then(function(r){ return r.ok ? r.text() : ''; })
    .then(function(t){ var m = /"mainPack":"([^"]+)"/.exec(t || ''); if (m) U.got = m[1]; U.at = Date.now(); })
    .catch(function(){})
    .then(function(){ U.busy = false; });
  return 1;
})()
"""
const JS_RELOAD := """
(function(){
  try { fetch(location.pathname, { cache: 'reload', credentials: 'omit' }).catch(function(){}).then(function(){ location.reload(); }); }
  catch (e) { location.reload(); }
  return 1;
})()
"""

var stage
var tracker
var _on := false
var _t := 20.0          # 1ª checagem 20 s depois de abrir
var _snooze := 0.0
var pending := false
var _asking := false
var _was_game := false
var test_force := false  # testes: finge que saiu versão nova

func setup(p_stage, p_tracker):
	stage = p_stage
	tracker = p_tracker
	if OS.has_feature("web"):
		var cur = JavaScriptBridge.eval(JS_SETUP, true)
		_on = cur != null and not String(cur).is_empty()

func _process(delta):
	_snooze = maxf(0.0, _snooze - delta)
	if _on and not pending:
		_t -= delta
		if _t <= 0.0:
			_t = CHECK_EVERY
			JavaScriptBridge.eval(JS_CHECK, true)
		var got = JavaScriptBridge.eval("(window.__fraihaUpd && window.__fraihaUpd.got) || ''", true)
		var cur = JavaScriptBridge.eval("(window.__fraihaUpd && window.__fraihaUpd.cur) || ''", true)
		if got != null and not String(got).is_empty() and String(got) != String(cur): pending = true
	if test_force: pending = true
	if not pending or _asking: return
	var game: bool = tracker != null and tracker.in_game()
	if game:
		_was_game = true
		return
	if _was_game:   # acabou de voltar de uma partida: pergunta de novo mesmo adiado
		_was_game = false
		_snooze = 0.0
	if _snooze > 0.0: return
	_ask()

func _ask():
	var hub = stage.get("hub") if stage != null else null
	if hub == null or not hub.has_method("ask"): return
	_asking = true
	_snooze = SNOOZE
	hub.ask("NOVA ATUALIZAÇÃO", "Saiu uma versão nova do FRAIHA Xadrez, com melhorias e correções.\nAtualize agora para jogar na versão mais recente (leva só alguns segundos).",
		"ATUALIZAR AGORA", "DEPOIS", func(): reload_now())
	# a janela fecha sozinha (sim ou não); libera para perguntar de novo depois do adiamento
	var modal = hub.get("notice_modal")
	if modal != null and modal.has_signal("closed"): modal.closed.connect(func(): _asking = false, CONNECT_ONE_SHOT)
	else: get_tree().create_timer(2.0).timeout.connect(func(): _asking = false)

func reload_now():
	if OS.has_feature("web"): JavaScriptBridge.eval(JS_RELOAD, true)
