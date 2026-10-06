extends Node
## FRAIHA Voice · interface do provedor de voz (Agora hoje; trocável sem mexer nos modos de jogo).
## Os modos NUNCA usam isto direto: só FraihaVoice (voice/fraiha_voice.gd) fala com o provedor.
## Tudo que o provedor conta para o FraihaVoice chega pelo sinal `event` como Dictionary:
##   {ev: "permission"|"mic_ready"|"joined"|"left"|"state"|"remote"|"speaking"|"will_expire"|"expired"
##        |"muted"|"speaker"|"renewed"|"mic_lost"|"autoplay_blocked"|"autoplay_ok"|"device_changed"|"error"|"warn"|
##        "sdk_loading"|"sdk_ready", seq: int, ...}
## seq = número da tentativa (o FraihaVoice descarta eventos de tentativas antigas).
signal event(data: Dictionary)

## "" = suportado; senão o motivo ("not_web", "insecure", "no_media", "no_webrtc").
func unsupported_reason() -> String: return "not_implemented"
## Suporte + contexto seguro + permissão do microfone + trilha local (antes do token).
func prepare(_seq: int) -> void: pass
## cfg = {app_id, channel, token, uid, muted, speaker_muted}. Entra no canal e publica o microfone.
func join(_seq: int, _cfg: Dictionary) -> void: pass
## Sai do canal, para/fecha a trilha, remove listeners. Idempotente.
func leave(_seq: int, _reason := "") -> void: pass
func set_muted(_on: bool) -> void: pass
func renew(_token: String) -> void: pass
## Áudio RECEBIDO (alto-falante da voz): on = não ouvir ninguém. Continua na sala; microfone intocado.
func set_speaker_muted(_on: bool) -> void: pass
## Mute LOCAL de um participante (uid = assento). Só eu deixo de ouvi-lo.
func set_remote_muted(_uid: int, _on: bool) -> void: pass
