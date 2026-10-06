extends Control
## R46 · PLACA do jogador na partida de xadrez online (Casual/Ranked/amigo) — proposta A aprovada.
## Só desenho (nunca regra): fundo, borda dupla dourada no tom da LIGA (Ranked), cravos nos cantos, borda
## acesa para quem está com o relógio e, da voz: fone no canto do retrato (na sala / falando / silenciado)
## e brilho verde em volta do retrato de quem está falando. Fica por trás do conteúdo da faixa.
const VoiceGlyph := preload("res://voice/voice_glyph.gd")
var accent := Color("f4ce7f")
var active := false
var speaking := false
var portrait_rect := Rect2()
var voice_state := ""
var front := false      # true = camada da FRENTE (só a voz, por cima do retrato/moldura)   # "" fora da voz | "in" na sala | "speaking" falando | "deaf" eu silenciei a voz dele

func _init():
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw():
    if front:
        _draw_voice()
        return
    var r := Rect2(Vector2.ZERO, size)
    var dim := accent.darkened(0.45)
    draw_rect(r, Color(0.04, 0.07, 0.055, 0.92))
    # faixa de cima mais clara (pergaminho escuro) para dar volume
    draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.y * 0.42)), Color(1, 1, 1, 0.025))
    draw_rect(r.grow(-1), accent if active else dim, false, 2.0)
    draw_rect(r.grow(-5), Color(accent, 0.35 if active else 0.18), false, 1.0)
    for c in [Vector2(7, 7), Vector2(size.x - 7, 7), Vector2(7, size.y - 7), Vector2(size.x - 7, size.y - 7)]:
        draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3.5), c + Vector2(3.5, 0), c + Vector2(0, 3.5), c + Vector2(-3.5, 0)]), accent if active else dim)

func _draw_voice():
    if speaking and portrait_rect.size.x > 0:
        var pr := portrait_rect.grow(4)
        for i in 3: draw_rect(pr.grow(i * 1.5), Color(0.5, 0.95, 0.5, 0.55 - i * 0.17), false, 2.0)
    if voice_state != "" and portrait_rect.size.x > 0:
        var side := clampf(portrait_rect.size.x * 0.36, 14.0, 26.0)
        var b := Rect2(portrait_rect.position + Vector2(-side * 0.25, portrait_rect.size.y - side * 0.75), Vector2(side, side))
        draw_circle(b.get_center(), side * 0.55, Color("0b150f"))
        draw_arc(b.get_center(), side * 0.55, 0, TAU, 16, Color(accent, 0.8), 1.5)
        VoiceGlyph.draw_headphones(self, b.grow(-side * 0.12), voice_state == "deaf", Color("8fe28a") if voice_state == "speaking" else Color("f4ce7f"))
