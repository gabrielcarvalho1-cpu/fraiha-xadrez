extends Node
## Foto de perfil: cache local + download da URL pública (Storage) + utilitários de imagem.
##
## Onde fica a foto:
##   • CLIENTE: user://avatars/<chave>.webp (chave = user_id da conta, ou "local" sem conta).
##     Só um cache/visualização — nunca é a fonte oficial.
##   • SERVIDOR: Supabase Storage, bucket público "avatars", arquivo <user_id>.webp (512x512),
##     gravado pelo backend Node (service_role) e referenciado em profiles.avatar_url.
##     O cliente manda os bytes já recortados (acct_avatar_upload); o servidor revalida.
## Nunca se guarda caminho local do Windows nem base64 gigante no perfil.
signal texture_ready(key: String)

const SIZE := 512
const MAX_UPLOAD := 400 * 1024
const DIR := "user://avatars"

var textures := {}        # key -> ImageTexture
var pending := {}         # url -> key (downloads em andamento)

static func local_path(key: String) -> String:
    return DIR + "/" + key.validate_filename() + ".webp"

func texture_for(key: String) -> Texture2D:
    if textures.has(key): return textures[key]
    var path := local_path(key)
    if FileAccess.file_exists(path):
        var img := Image.new()
        if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
            textures[key] = ImageTexture.create_from_image(img)
            return textures[key]
    return null

func has_local(key: String) -> bool:
    return textures.has(key) or FileAccess.file_exists(local_path(key))

## Guarda a imagem final (já 512x512) no cache local e devolve os bytes WebP para upload.
func save_local(key: String, img: Image) -> PackedByteArray:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
    var bytes := encode_webp(img)
    var f := FileAccess.open(local_path(key), FileAccess.WRITE)
    if f != null:
        f.store_buffer(bytes)
        f.close()
    textures[key] = ImageTexture.create_from_image(img)
    texture_ready.emit(key)
    return bytes

func clear_local(key: String):
    textures.erase(key)
    var path := local_path(key)
    if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    texture_ready.emit(key)

## WebP com perda, baixando a qualidade até caber no limite de upload.
static func encode_webp(img: Image) -> PackedByteArray:
    var q := 0.88
    var bytes := img.save_webp_to_buffer(true, q)
    while bytes.size() > MAX_UPLOAD and q > 0.4:
        q -= 0.1
        bytes = img.save_webp_to_buffer(true, q)
    return bytes

## Baixa a foto pública (profiles.avatar_url) para o cache local, se ainda não existir.
func fetch(key: String, url: String):
    if url.is_empty() or not url.begins_with("http") or pending.has(url): return
    if has_local(key) and textures.has(key): return
    var req := HTTPRequest.new()
    req.timeout = 20.0
    add_child(req)
    pending[url] = key
    req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
        pending.erase(url)
        req.queue_free()
        if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty(): return
        var img := decode(body)
        if img == null: return
        if img.get_width() != SIZE or img.get_height() != SIZE: img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
        save_local(key, img))
    if req.request(url) != OK:
        pending.erase(url)
        req.queue_free()

# ---------- Decodificação (PNG / JPG / WebP) com orientação EXIF ----------
static func sniff(bytes: PackedByteArray) -> String:
    if bytes.size() > 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP": return "webp"
    if bytes.size() > 8 and bytes[0] == 0x89 and bytes.slice(1, 4).get_string_from_ascii() == "PNG": return "png"
    if bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF: return "jpg"
    return ""

static func decode(bytes: PackedByteArray) -> Image:
    var kind := sniff(bytes)
    if kind.is_empty(): return null
    var img := Image.new()
    var err := ERR_INVALID_DATA
    match kind:
        "png": err = img.load_png_from_buffer(bytes)
        "jpg": err = img.load_jpg_from_buffer(bytes)
        "webp": err = img.load_webp_from_buffer(bytes)
    if err != OK or img.is_empty(): return null
    if kind == "jpg": apply_exif_orientation(img, exif_orientation(bytes))
    if img.get_format() != Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
    return img

## Lê a tag Orientation (0x0112) do EXIF de um JPEG; 1 = normal.
static func exif_orientation(bytes: PackedByteArray) -> int:
    var i := 2
    while i + 4 < bytes.size():
        if bytes[i] != 0xFF: return 1
        var marker := bytes[i + 1]
        var seg_len := (bytes[i + 2] << 8) | bytes[i + 3]
        if marker == 0xE1 and i + 10 < bytes.size() and bytes[i + 4] == 0x45 and bytes[i + 5] == 0x78 and bytes[i + 6] == 0x69 and bytes[i + 7] == 0x66:
            var t := i + 10   # início do TIFF
            if t + 8 > bytes.size(): return 1
            var le := bytes[t] == 0x49
            var rd16 := func(p: int) -> int: return (bytes[p] | (bytes[p + 1] << 8)) if le else ((bytes[p] << 8) | bytes[p + 1])
            var rd32 := func(p: int) -> int: return (bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16) | (bytes[p + 3] << 24)) if le else ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3])
            var ifd: int = t + rd32.call(t + 4)
            if ifd + 2 > bytes.size(): return 1
            var count: int = rd16.call(ifd)
            for k in count:
                var e := ifd + 2 + k * 12
                if e + 12 > bytes.size(): return 1
                if rd16.call(e) == 0x0112: return rd16.call(e + 8)
            return 1
        if marker == 0xDA: return 1
        i += 2 + seg_len
    return 1

static func apply_exif_orientation(img: Image, o: int):
    match o:
        2: img.flip_x()
        3: img.rotate_180()
        4: img.flip_y()
        5: img.rotate_90(CLOCKWISE); img.flip_x()
        6: img.rotate_90(CLOCKWISE)
        7: img.rotate_90(COUNTERCLOCKWISE); img.flip_x()
        8: img.rotate_90(COUNTERCLOCKWISE)
