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
    draw_rect(r, Color(0.057, 0.071, 0.099, 0.92))
    # faixa de cima mais clara (pergaminho escuro) para dar volume
    draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.y * 0.42)), Color(1, 1, 1, 0.025))
    draw_rect(r.grow(-1), accent if active else dim, false, 2.0)
    draw_rect(r.grow(-5), Color(accent, 0.35 if active else 0.18), false, 1.0)
    for c in [Vector2(7, 7), Vector2(size.x - 7, 7), Vector2(7, size.y - 7), Vector2(size.x - 7, size.y - 7)]:
        draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3.5), c + Vector2(3.5, 0), c + Vector2(0, 3.5), c + Vector2(-3.5, 0)]), accent if active else dim)

func _draw_voice():
    if portrait_rect.size.x <= 0: return
    # R173 · tudo da voz fica DENTRO da placa (sem cobrir a borda dupla, o relógio nem o vizinho) e colado no
    # retrato. O retrato é retangular (avatar quadrado ou medalhão redondo; no celular a placa não tem moldura
    # premium), então o brilho segue o retângulo do retrato, justo.
    var inner := Rect2(Vector2.ZERO, size).grow(-6.0)
    if speaking:
        for i in 2:
            var g := portrait_rect.grow(1.5 + i * 1.5).intersection(inner)
            if g.size.x > 0 and g.size.y > 0: draw_rect(g, Color(0.5, 0.95, 0.5, 0.85 - i * 0.4), false, 2.0)
    if voice_state != "":
        var side := clampf(portrait_rect.size.x * 0.36, 14.0, 26.0)
        var rad := side * 0.55
        # fone no canto de baixo à esquerda do retrato, por dentro da placa
        var c := portrait_rect.position + Vector2(side * 0.38, portrait_rect.size.y - side * 0.38)
        c.x = clampf(c.x, inner.position.x + rad, inner.end.x - rad)
        c.y = clampf(c.y, inner.position.y + rad, inner.end.y - rad)
        var b := Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side))
        draw_circle(c, rad, Color("10141e"))
        draw_arc(c, rad, 0, TAU, 16, Color(accent, 0.8), 1.5)
        VoiceGlyph.draw_headphones(self, b.grow(-side * 0.12), voice_state == "deaf", Color("8fe28a") if voice_state == "speaking" else Color("f4ce7f"))
