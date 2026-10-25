extends Node
## Escolha de imagem do computador/celular. Desktop: diálogo nativo do Godot (FileDialog);
## Web: <input type="file"> do navegador via JavaScriptBridge (abre a galeria no celular).
## Devolve os bytes do arquivo; quem chama decodifica/valida.
signal picked(bytes: PackedByteArray, filename: String)
signal failed(message: String)

const MAX_FILE := 12 * 1024 * 1024   # 12 MB antes do recorte (o recorte final fica ≤ 400 KB)
const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

var dialog: FileDialog
var _web_cb: JavaScriptObject

var _native = null

func open():
    if OS.has_feature("web"):
        _open_web()
    elif _android_native():
        _native.pickImage()
    else:
        _open_desktop()

## R185 · app Android: galeria nativa pelo plugin (lê pelo ContentResolver e devolve JPEG pronto).
## O FileDialog do Godot devolvia um caminho ilegível no Android 10+ e a foto nunca mudava.
func _android_native() -> bool:
    if not OS.has_feature("android"): return false
    if _native == null and Engine.has_singleton("FraihaVoice"):
        var n = Engine.get_singleton("FraihaVoice")
        if n.has_method("pickImage") and n.has_signal("image_picked"):
            _native = n
            _native.connect("image_picked", _on_native_image)
    return _native != null

func _on_native_image(kind: String, data: String):
    match kind:
        "ok":
            var bytes := Marshalls.base64_to_raw(data)
            if bytes.is_empty() or sniff(bytes) == "":
                failed.emit("Não foi possível ler a foto.")
                return
            picked.emit(bytes, "foto.jpg")
        "cancel":
            pass
        _:
            failed.emit("Não foi possível abrir essa foto. Tente outra.")

func _open_desktop():
    if dialog == null:
        dialog = FileDialog.new()
        dialog.name = "AvatarFileDialog"
        dialog.access = FileDialog.ACCESS_FILESYSTEM
        dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
        dialog.use_native_dialog = true
        dialog.title = "Escolher foto de perfil"
        dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imagens"])
        dialog.file_selected.connect(_on_file)
        dialog.size = Vector2i(900, 600)
        add_child(dialog)
    dialog.popup_centered()

func _on_file(path: String):
    # R184e · app Android: a galeria devolve content://… (sem extensão no nome) — o formato é conferido pelos
    # primeiros bytes do arquivo (antes recusava toda foto em silêncio e a foto nunca mudava)
    var ext := path.get_extension().to_lower()
    if ext != "" and ext not in EXTENSIONS and not path.begins_with("content://"):
        failed.emit("Formato não aceito. Use PNG, JPG ou WebP.")
        return
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        failed.emit("Não foi possível ler o arquivo.")
        return
    if bytes.size() > MAX_FILE:
        failed.emit("Arquivo grande demais (máximo 12 MB).")
        return
    var kind := sniff(bytes)
    if kind == "":
        failed.emit("Formato não aceito. Use PNG, JPG ou WebP.")
        return
    var fname := path.get_file()
    if fname.get_extension().to_lower() not in EXTENSIONS: fname = "foto." + kind
    picked.emit(bytes, fname)

## "png" | "jpg" | "webp" | "" pelos primeiros bytes
static func sniff(b: PackedByteArray) -> String:
    if b.size() >= 8 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47: return "png"
    if b.size() >= 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF: return "jpg"
    if b.size() >= 12 and b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP": return "webp"
    return ""

func _open_web():
    if _web_cb == null:
        _web_cb = JavaScriptBridge.create_callback(_on_web_result)
        JavaScriptBridge.get_interface("window").fraihaPickCb = _web_cb
    JavaScriptBridge.eval("""
    (() => {
        const inp = document.createElement('input');
        inp.type = 'file'; inp.accept = 'image/png,image/jpeg,image/webp';
        inp.style.display = 'none';
        document.body.appendChild(inp);
        inp.addEventListener('change', () => {
            const f = inp.files && inp.files[0];
            if (!f) { window.fraihaPickCb('cancel', '', ''); inp.remove(); return; }
            if (f.size > %d) { window.fraihaPickCb('error', 'Arquivo grande demais (máximo 12 MB).', ''); inp.remove(); return; }
            const r = new FileReader();
            r.onload = () => {
                const b = new Uint8Array(r.result); let s = '';
                for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
                window.fraihaPickCb('ok', btoa(s), f.name); inp.remove();
            };
            r.onerror = () => { window.fraihaPickCb('error', 'Não foi possível ler o arquivo.', ''); inp.remove(); };
            r.readAsArrayBuffer(f);
        });
        inp.click();
    })()
    """ % MAX_FILE)

## O navegador chama fraihaPickCb(tipo, dados, nome) com 3 strings. O Godot entrega os argumentos
## do JS como um Array de Variants; um array JS viraria JavaScriptObject (não Array) e era
## descartado em silêncio — por isso o editor de foto nunca abria na Web.
func _on_web_result(args: Array):
    if args.size() < 3:
        failed.emit("Não foi possível ler o arquivo.")
        return
    var kind := str(args[0])
    if kind == "ok":
        var bytes := Marshalls.base64_to_raw(str(args[1]))
        var fname := str(args[2])
        if bytes.is_empty():
            failed.emit("Não foi possível ler o arquivo.")
            return
        if fname.get_extension().to_lower() not in EXTENSIONS and fname.get_extension() != "":
            failed.emit("Formato não aceito. Use PNG, JPG ou WebP.")
            return
        picked.emit(bytes, fname)
    elif kind == "error":
        failed.emit(str(args[1]))
