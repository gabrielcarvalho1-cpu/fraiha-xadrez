extends HBoxContainer
## FRAIHA Voice · controle do Xadrez online (Casual/Ranked/amigo): botão do microfone + estado.
## Só aparece com partida online contra humano e navegador com suporte. Toque: entrar → mudo ↔ falar.
## O "×" sai da voz (a partida continua).
const HudButton := preload("res://ui_v022/hud_button.gd")
const Glyph := preload("res://voice/voice_glyph.gd")

var voice = null
var mic: Button
var off: Button
var label: Label
var compact := false   # celular: sem texto ao lado (o texto vai no tooltip)

func setup(v, mobile := false) -> void:
    voice = v
    compact = mobile
    name = "VoiceControl"
    add_theme_constant_override("separation", 6)
    alignment = BoxContainer.ALIGNMENT_CENTER
    size_flags_vertical = Control.SIZE_SHRINK_CENTER
    mic = HudButton.make("sound_on")
    mic.name = "VoiceMic"
    mic.glyph = ""
    mic.custom_minimum_size = Vector2(54, 54) if not mobile else Vector2(48, 44)
    mic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    mic.pressed.connect(func(): if voice != null: voice.press())
    mic.draw.connect(_draw_mic)
    add_child(mic)
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
    add_child(off)
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
    label.visible = not mobile
    add_child(label)
    voice.changed.connect(refresh)
    refresh()

func refresh() -> void:
    if voice == null: return
    visible = voice.in_match() and voice.available()
    var st: String = voice.state
    off.visible = voice.active() or st == "ERROR"
    var txt: String = voice.status_text()
    label.text = txt
    mic.tooltip_text = {"DISCONNECTED": "Entrar na voz", "CONNECTED": "Ficar mudo", "MUTED": "Ligar o microfone", "ERROR": "Tentar de novo"}.get(st, "Voz") + " — " + txt
    mic.queue_redraw()
    set_process(st in ["REQUESTING_PERMISSION", "CONNECTING", "RECONNECTING"] or st == "CONNECTED")

func _process(_d):
    if mic != null: mic.queue_redraw()

func _draw_mic():
    if voice == null: return
    var r := Rect2(Vector2.ZERO, mic.size).grow(-9)
    Glyph.draw_mic(mic, r, voice.state, Color("f4ce7f"), voice.is_speaking(voice.my_uid))
