extends BoxContainer
## FRAIHA Voice · controle do Xadrez online (Casual/Ranked/amigo): botão do microfone + estado.
## Só aparece com partida online contra humano e navegador com suporte. Toque: entrar → mudo ↔ falar.
## O "×" sai da voz (a partida continua). Desktop: [mic ×] estado ao lado; celular: estado embaixo.
const HudButton := preload("res://ui_v022/hud_button.gd")
const Glyph := preload("res://voice/voice_glyph.gd")

var voice = null
var mic: Button
var off: Button
var ear: Button     # ÁUDIO RECEBIDO da voz (fone): ouvir / não ouvir os outros, sem sair da sala
var label: Label
var compact := false   # celular: estado numa linha embaixo do microfone

func setup(v, mobile := false) -> void:
    voice = v
    compact = mobile
    name = "VoiceControl"
    vertical = mobile
    add_theme_constant_override("separation", 6 if not mobile else 2)
    alignment = BoxContainer.ALIGNMENT_CENTER
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    add_child(row)
    size_flags_vertical = Control.SIZE_SHRINK_CENTER
    mic = HudButton.make("sound_on")
    mic.name = "VoiceMic"
    mic.glyph = ""
    mic.custom_minimum_size = Vector2(54, 54) if not mobile else Vector2(48, 44)
    mic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    mic.pressed.connect(func(): if voice != null: voice.press())
    mic.draw.connect(_draw_mic)
    row.add_child(mic)
    ear = HudButton.make("sound_on")
    ear.name = "VoiceSpeaker"
    ear.glyph = ""
    ear.custom_minimum_size = Vector2(44, 44) if not mobile else Vector2(44, 44)
    ear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    ear.pressed.connect(func(): if voice != null: voice.toggle_speaker())
    ear.draw.connect(func():
        if voice == null: return
        Glyph.draw_headphones(ear, Rect2(Vector2.ZERO, ear.size).grow(-8), voice.speaker_muted, Color("f4ce7f")))
    row.add_child(ear)
    off = HudButton.make("sound_on")
    off.name = "VoiceLeave"
    off.glyph = ""
    off.icon_only = true
    off.draw.connect(func():
        var c: Vector2 = off.size / 2.0
        var a := 5.0
        var col := Color("f4ce7f") if off.is_hovered() else Color("e9cf8f")
        off.draw_line(c + Vector2(-a, -a), c + Vector2(a, a), col, 2.0)
        off.draw_line(c + Vector2(-a, a), c + Vector2(a, -a), col, 2.0))
    off.tooltip_text = "Sair da voz (a partida continua)"
    off.custom_minimum_size = Vector2(30, 30)
    off.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    off.pressed.connect(func(): if voice != null: voice.leave("user"))
    row.add_child(off)
    label = Label.new()
    label.name = "VoiceStatus"
    label.add_theme_font_size_override("font_size", 13)
    label.add_theme_color_override("font_color", Color("e8dcc0"))
    label.add_theme_color_override("font_outline_color", Color("0b150f"))
    label.add_theme_constant_override("outline_size", 3)
    label.custom_minimum_size = Vector2(150, 0)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.max_lines_visible = 2
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if mobile:
        label.custom_minimum_size = Vector2(0, 0)
        label.add_theme_font_size_override("font_size", 12)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(label)
    if mobile and get_parent() is BoxContainer:
        # celular em pé: a coluna vira UMA linha embaixo do tabuleiro; ali o texto não cabe (só o ícone)
        get_parent().sort_children.connect(_fit)
    voice.changed.connect(refresh)
    refresh()

func refresh() -> void:
    if voice == null: return
    visible = voice.in_match() and voice.available()
    var st: String = voice.state
    off.visible = voice.active() or st == "ERROR"
    ear.visible = voice.active()
    ear.tooltip_text = "Voltar a ouvir a voz" if voice.speaker_muted else "Silenciar a voz recebida (continuo na sala; meu microfone não muda)"
    ear.queue_redraw()
    var txt: String = voice.status_text()
    label.text = txt
    _fit()
    mic.tooltip_text = {"DISCONNECTED": "Entrar na voz", "CONNECTED": "Ficar mudo", "MUTED": "Ligar o microfone", "ERROR": "Tentar de novo"}.get(st, "Voz") + " — " + txt
    mic.queue_redraw()
    set_process(st in ["REQUESTING_PERMISSION", "CONNECTING", "RECONNECTING"] or st == "CONNECTED")

func _process(_d):
    if mic != null: mic.queue_redraw()

func _draw_mic():
    if voice == null: return
    var r := Rect2(Vector2.ZERO, mic.size).grow(-9)
    Glyph.draw_mic(mic, r, voice.state, Color("f4ce7f"), voice.is_speaking(voice.my_uid))

func _fit() -> void:
    if label == null: return
    var host = get_parent()
    var want: bool = not compact or (host is BoxContainer and bool(host.vertical))
    if label.visible != want: label.visible = want
