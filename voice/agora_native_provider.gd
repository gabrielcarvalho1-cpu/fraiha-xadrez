extends "res://voice/voice_provider.gd"
## R183 · FRAIHA Voice no APP ANDROID: provedor que fala com o plugin nativo "FraihaVoice" (Agora Android SDK,
## android_plugin/fraiha_voice/FraihaVoicePlugin.kt). Mesmos eventos do provedor da Web → FraihaVoice não muda.
## Microfone: permissão RECORD_AUDIO pedida pelo próprio Android (OS.request_permission).
## R188 · APP DE IPHONE: o mesmo provedor fala com o plugin nativo do iOS (ios_plugin/fraiha_ios/fraiha_ios.mm), que
## registra o mesmo singleton "FraihaVoice"; lá a permissão do microfone é pedida pelo plugin (requestMic).

const MIC := "android.permission.RECORD_AUDIO"
var plugin = null
var _perm_seq := -1

func _ready():
	if Engine.has_singleton("FraihaVoice"):
		plugin = Engine.get_singleton("FraihaVoice")
		plugin.connect("voice_event", _on_native)
	if OS.has_feature("android"): get_tree().on_request_permissions_result.connect(_on_permission)
	if OS.has_feature("ios"): print("[FraihaVoice] plugin nativo do iPhone: ", "ok" if plugin != null else "AUSENTE")

func unsupported_reason() -> String:
	if not (OS.has_feature("android") or OS.has_feature("ios")): return "not_android"
	if plugin == null: return "no_native"
	return ""

static func mic_granted() -> bool:
	return MIC in OS.get_granted_permissions()

func prepare(seq: int) -> void:
	event.emit({"ev": "permission", "seq": seq})
	if OS.has_feature("ios"):   # o plugin responde mic_ready ou error PERMISSION_DENIED pelo voice_event
		if plugin == null: event.emit({"ev": "error", "seq": seq, "stage": "sdk", "code": "SDK_LOAD"})
		else: plugin.requestMic(seq)
		return
	if mic_granted():
		event.emit({"ev": "mic_ready", "seq": seq})
		return
	_perm_seq = seq
	if OS.request_permission(MIC):   # já concedida (Android antigo): segue
		_perm_seq = -1
		event.emit({"ev": "mic_ready", "seq": seq})

func _on_permission(permission: String, granted: bool) -> void:
	if permission != MIC or _perm_seq < 0: return
	var seq := _perm_seq
	_perm_seq = -1
	if granted: event.emit({"ev": "mic_ready", "seq": seq})
	else: event.emit({"ev": "error", "seq": seq, "stage": "mic", "code": "PERMISSION_DENIED"})

func join(seq: int, cfg: Dictionary) -> void:
	if plugin == null:
		event.emit({"ev": "error", "seq": seq, "stage": "sdk", "code": "SDK_LOAD"})
		return
	plugin.join(seq, String(cfg.get("app_id", "")), String(cfg.get("channel", "")), String(cfg.get("token", "")),
		int(cfg.get("uid", 0)), bool(cfg.get("muted", false)), bool(cfg.get("speaker_muted", false)))

func leave(seq: int, reason := "") -> void:
	_perm_seq = -1
	if plugin != null: plugin.leave(seq, reason)

func set_muted(on: bool) -> void:
	if plugin != null: plugin.setMuted(on)

func set_speaker_muted(on: bool) -> void:
	if plugin != null: plugin.setSpeakerMuted(on)

func set_remote_muted(uid: int, on: bool) -> void:
	if plugin != null: plugin.setRemoteMuted(uid, on)

func renew(token: String) -> void:
	if plugin != null: plugin.renew(token)

func _on_native(json: String) -> void:
	var d = JSON.parse_string(json)
	if d is Dictionary: event.emit(d)
