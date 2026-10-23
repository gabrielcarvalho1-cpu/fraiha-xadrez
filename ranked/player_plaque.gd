extends Control
## R46 · PLACA do jogador na partida de xadrez online (Casual/Ranked/amigo) — proposta A aprovada.
## Só desenho (nunca regra): fundo, borda dupla dourada no tom da LIGA (Ranked), cravos nos cantos, borda
## acesa para quem está com o relógio e, da voz: fone no canto do retrato (na sala / falando / silenciado)
## e anel verde em volta do retrato de quem está falando (R180e: sem o fone). Fica por trás do conteúdo da faixa.
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
    draw_rect(r, Color(0.057, 0.071, 0.099, 0.92))
    # faixa de cima mais clara (pergaminho escuro) para dar volume
    draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.y * 0.42)), Color(1, 1, 1, 0.025))
    draw_rect(r.grow(-1), accent if active else dim, false, 2.0)
    draw_rect(r.grow(-5), Color(accent, 0.35 if active else 0.18), false, 1.0)
    for c in [Vector2(7, 7), Vector2(size.x - 7, 7), Vector2(7, size.y - 7), Vector2(size.x - 7, size.y - 7)]:
        draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3.5), c + Vector2(3.5, 0), c + Vector2(0, 3.5), c + Vector2(-3.5, 0)]), accent if active else dim)

func _draw_voice():
    if portrait_rect.size.x <= 0: return
    # R180e · sem o fone no canto do retrato (ficava feio): só o ANEL VERDE em volta da foto enquanto a pessoa fala.
    # O retrato é um medalhão redondo: o anel acompanha o círculo, por dentro da placa.
    if not speaking: return
    var inner := Rect2(Vector2.ZERO, size).grow(-4.0)
    var c := portrait_rect.get_center()
    var r := minf(portrait_rect.size.x, portrait_rect.size.y) / 2.0
    var w := clampf(r * 0.09, 2.0, 4.0)
    for i in 3:
        var rr := r + w * (0.2 + i * 0.9)
        if c.x - rr < inner.position.x - 1.0 or c.y - rr < inner.position.y - 1.0 or c.y + rr > inner.end.y + 1.0: rr = minf(rr, minf(c.x - inner.position.x, minf(c.y - inner.position.y, inner.end.y - c.y)))
        draw_arc(c, rr, 0.0, TAU, 64, Color(0.45, 1.0, 0.45, [0.95, 0.5, 0.2][i]), w if i == 0 else w * 0.8, true)
