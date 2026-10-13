extends RefCounted
## R89 · Sprite2D grande que fica escondido boa parte do tempo (floresta atrás do tabuleiro no celular):
## escondido → solta a textura; visível de novo → carrega do mesmo arquivo. Nada muda no desenho.
static func attach(sp: Sprite2D) -> void:
    if sp == null or sp.has_meta("sleepy"): return
    sp.set_meta("sleepy", true)
    sp.visibility_changed.connect(func(): _sync(sp))
    _sync(sp)

static func _sync(sp: Sprite2D) -> void:
    if not is_instance_valid(sp): return
    if not sp.is_visible_in_tree():
        if sp.texture != null and sp.texture.resource_path != "":
            sp.set_meta("sleepy_path", sp.texture.resource_path)
            sp.texture = null
    elif sp.texture == null and sp.has_meta("sleepy_path"):
        sp.texture = load(String(sp.get_meta("sleepy_path")))
