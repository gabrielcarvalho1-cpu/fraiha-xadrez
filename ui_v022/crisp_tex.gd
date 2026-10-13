extends RefCounted
## R37.2 · Arte grande desenhada pequena (cartas na mão): o projeto usa filtro NEAREST (pixel art), então
## reduzir uma carta de 500 px para ~150 px pulava pixels e o texto ficava ilegível. Aqui a textura é
## reduzida UMA vez com Lanczos para o tamanho real na tela (em pixels) e guardada; desenhada 1:1 fica nítida.
##
## R61 · fonte na CPU, sem ler a GPU: antes cada tamanho novo chamava Texture2D.get_image(), que na Web vira
## WebGL readPixels (síncrono, ~250–1000 ms por carta no navegador) — o pico na distribuição do XEQUE.
## Agora a imagem de origem é decodificada UMA vez do próprio arquivo importado (.ctex: WebP/PNG sem perda,
## os mesmos pixels que foram para a GPU) e guardada; os tamanhos saem dela na CPU. get_image() só fica como
## último recurso (textura sem arquivo importado legível), e é contado em `readbacks`.
static var _cache := {}
static var _src := {}                 # id da textura -> Image de origem (CPU), poucas por vez
const SRC_KEEP := 2
static var readbacks := 0             # get_image() feitos (leitura da GPU; readPixels na Web) — deve ficar 0
static var readback_ms := 0.0

## Textura reduzida para `px` (largura × altura em pixels de TELA). Tamanhos parecidos reutilizam a mesma.
static func at(tex: Texture2D, px: Vector2) -> Texture2D:
    if tex == null: return tex
    var src := tex.get_size()
    var w := int(round(px.x))
    if w <= 0 or float(w) >= src.x * 0.92: return tex          # quase do tamanho do arquivo: usa o original
    w = int(round(w / 4.0)) * 4                                # degraus de 4 px (cache pequeno ao redimensionar)
    var h := int(round(w * src.y / src.x))
    var key := "%d_%d" % [tex.get_rid().get_id(), w]
    if _cache.has(key):
        # R89 · LRU: o usado agora vai para o fim (os mais antigos saem primeiro)
        var hit = _cache[key]
        _cache.erase(key)
        _cache[key] = hit
        return hit
    var base := source_image(tex)
    if base == null: return tex
    var img := base.duplicate()
    img.resize(w, h, Image.INTERPOLATE_LANCZOS)
    var out := ImageTexture.create_from_image(img)
    # R89 · limite em BYTES (antes: 160 texturas — até ~140 MB com cartas grandes animando no celular)
    _bytes += w * h * 4
    _cache[key] = out
    _sizes[key] = w * h * 4
    while _bytes > _budget() and _cache.size() > 1:
        var old_key = _cache.keys()[0]
        _bytes -= int(_sizes.get(old_key, 0))
        _cache.erase(old_key)
        _sizes.erase(old_key)
    return out

static var _bytes := 0
static var _sizes := {}
static var _budget_cache := -1
static func _budget() -> int:
    if _budget_cache < 0:
        var mobile: bool = preload("res://ui_v022/mobile_layout.gd").active(Engine.get_main_loop().root if Engine.get_main_loop() is SceneTree else null)
        _budget_cache = (20 if mobile else 64) * 1048576
    return _budget_cache

## R78 · solta tudo (reduções prontas + fontes): chamado ao fechar o XEQUE / a MARCHA, para a memória voltar
static func clear_cache() -> void:
    _cache.clear()
    _sizes.clear()
    _bytes = 0
    _src.clear()

## Solta as imagens de origem guardadas (as reduções prontas continuam). Chamado quando o preparo prévio acaba.
static func release_sources() -> void:
    _src.clear()

## Já existe a redução deste tamanho? (para preparar antes só o que falta)
static func has(tex: Texture2D, px: Vector2) -> bool:
    if tex == null: return true
    var w := int(round(px.x))
    if w <= 0 or float(w) >= tex.get_size().x * 0.92: return true
    w = int(round(w / 4.0)) * 4
    return _cache.has("%d_%d" % [tex.get_rid().get_id(), w])

## Imagem de origem na CPU (decodificada uma vez). Sem leitura da GPU quando o arquivo importado é legível.
static func source_image(tex: Texture2D) -> Image:
    var id := tex.get_rid().get_id()
    if _src.has(id): return _src[id]
    var img := _from_ctex(tex)
    if img == null:
        var t0 := Time.get_ticks_usec()
        img = tex.get_image()
        readbacks += 1; readback_ms += (Time.get_ticks_usec() - t0) / 1000.0
        if img == null: return null
    if img.is_compressed(): img.decompress()
    # memória: guarda só as últimas fontes usadas (cada carta grande ocupa ~1–3 MB na CPU); o verso da
    # distribuição e a carta da vez ficam, as outras saem (as reduções prontas continuam no _cache)
    while _src.size() >= SRC_KEEP: _src.erase(_src.keys()[0])
    _src[id] = img
    return img

## Lê o .ctex (formato GST2 do Godot 4) do arquivo importado da textura. Só os formatos sem perda guardados como
## WebP/PNG — exatamente os pixels enviados à GPU. Qualquer coisa diferente: null (usa get_image).
static func _from_ctex(tex: Texture2D) -> Image:
    if not (tex is CompressedTexture2D): return null
    var res_path := tex.resource_path
    if res_path.is_empty(): return null
    var path := ""
    var cfg := ConfigFile.new()
    if cfg.load(res_path + ".import") == OK: path = String(cfg.get_value("remap", "path", ""))
    if path.is_empty() and res_path.ends_with(".ctex"): path = res_path
    if path.is_empty(): return null
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return null
    if f.get_buffer(4).get_string_from_ascii() != "GST2": return null
    f.get_32()                                   # versão
    var w0 := f.get_32(); var h0 := f.get_32()
    f.get_32(); f.get_32(); f.get_32(); f.get_32(); f.get_32()   # flags, limite de mipmap, reservados
    var data_format := f.get_32()
    var w := f.get_16(); var h := f.get_16()
    var mipmaps := f.get_32()
    var fmt := f.get_32()
    if mipmaps != 0 or w != w0 or h != h0 or w != int(tex.get_width()) or h != int(tex.get_height()): return null
    var img: Image = null
    if data_format == 1 or data_format == 2:     # PNG / WebP
        var size := f.get_32()
        var buf := f.get_buffer(size)
        img = Image.new()
        var err := img.load_png_from_buffer(buf) if data_format == 1 else img.load_webp_from_buffer(buf)
        if err != OK: return null
        if img.get_format() != fmt: img.convert(fmt)
    else:
        return null                              # imagem crua/VRAM: não tratado aqui (usa get_image)
    if img == null or img.get_width() != w or img.get_height() != h: return null
    return img
