extends RefCounted
## R37.2 · Arte grande desenhada pequena (cartas na mão): o projeto usa filtro NEAREST (pixel art), então
## reduzir uma carta de 500 px para ~150 px pulava pixels e o texto ficava ilegível. Aqui a textura é
## reduzida UMA vez com Lanczos para o tamanho real na tela (em pixels) e guardada; desenhada 1:1 fica nítida.
static var _cache := {}

## Textura reduzida para `px` (largura × altura em pixels de TELA). Tamanhos parecidos reutilizam a mesma.
static func at(tex: Texture2D, px: Vector2) -> Texture2D:
    if tex == null: return tex
    var src := tex.get_size()
    var w := int(round(px.x))
    if w <= 0 or float(w) >= src.x * 0.92: return tex          # quase do tamanho do arquivo: usa o original
    w = int(round(w / 4.0)) * 4                                # degraus de 4 px (cache pequeno ao redimensionar)
    var h := int(round(w * src.y / src.x))
    var key := "%d_%d" % [tex.get_rid().get_id(), w]
    if _cache.has(key): return _cache[key]
    var img := tex.get_image()
    if img == null: return tex
    if img.is_compressed(): img.decompress()
    img = img.duplicate()
    img.resize(w, h, Image.INTERPOLATE_LANCZOS)
    var out := ImageTexture.create_from_image(img)
    if _cache.size() > 160: _cache.clear()
    _cache[key] = out
    return out
