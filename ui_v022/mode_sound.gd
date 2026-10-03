extends RefCounted
## R34 · áudio dos modos à parte (XEQUE e MARCHA REAL): música de fundo própria em loop enquanto o
## modo está aberto, efeitos sonoros de jogada pelo bus "Effects", e os dois botões MÚSICA / EFEITOS
## (desligam só a música ou só os efeitos; a preferência vale para o jogo inteiro e fica salva).

static func audio(stage):
    return stage.get_node_or_null("GameAudio") if stage != null else null

static func music_on(stage, path: String):
    var a = audio(stage)
    if a != null and a.has_method("set_music_override"): a.set_music_override(path)

static func music_off(stage):
    var a = audio(stage)
    if a != null and a.has_method("set_music_override"): a.set_music_override("")

static func play(stage, stream: AudioStream, db := -8.0, pitch := 1.0):
    var a = audio(stage)
    if a != null and a.has_method("play_stream"): a.play_stream(stream, db, pitch)

static func music_muted(hub) -> bool:
    return hub != null and bool(hub.get("music_muted"))

static func effects_muted(hub) -> bool:
    return hub != null and bool(hub.get("effects_muted"))

static func toggle_music(hub):
    if hub != null and hub.has_method("set_music_muted"): hub.set_music_muted(not music_muted(hub))

static func toggle_effects(hub):
    if hub != null and hub.has_method("set_effects_muted"): hub.set_effects_muted(not effects_muted(hub))

## Desenha o ícone dentro do quadrado r: "music" (nota) ou "fx" (alto-falante com ondas).
## Desligado = traço vermelho por cima.
static func glyph(ci: CanvasItem, r: Rect2, kind: String, off: bool, col: Color):
    var c := r.get_center()
    var u := r.size.y / 50.0
    if kind == "music":
        # duas colcheias ligadas
        ci.draw_circle(c + Vector2(-9, 10) * u, 5.5 * u, col)
        ci.draw_circle(c + Vector2(9, 6) * u, 5.5 * u, col)
        ci.draw_line(c + Vector2(-4, 10) * u, c + Vector2(-4, -12) * u, col, 3.0 * u)
        ci.draw_line(c + Vector2(14, 6) * u, c + Vector2(14, -16) * u, col, 3.0 * u)
        ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5.5, -12) * u, c + Vector2(15.5, -16) * u, c + Vector2(15.5, -10) * u, c + Vector2(-5.5, -6) * u]), col)
    else:
        ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-15, -5) * u, c + Vector2(-8, -5) * u, c + Vector2(1, -13) * u, c + Vector2(1, 13) * u, c + Vector2(-8, 5) * u, c + Vector2(-15, 5) * u]), col)
        if not off:
            ci.draw_arc(c + Vector2(2, 0) * u, 8.0 * u, -0.9, 0.9, 10, col, 2.5 * u)
            ci.draw_arc(c + Vector2(2, 0) * u, 14.0 * u, -0.9, 0.9, 14, col, 2.5 * u)
    if off:
        ci.draw_line(c + Vector2(-15, 15) * u, c + Vector2(15, -15) * u, Color("120a06"), 7.0 * u)
        ci.draw_line(c + Vector2(-15, 15) * u, c + Vector2(15, -15) * u, Color("e02a36"), 4.0 * u)
