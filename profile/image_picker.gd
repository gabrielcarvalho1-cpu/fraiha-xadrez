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

func open():
    if OS.has_feature("web"):
        _open_web()
    else:
        _open_desktop()

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
    if path.get_extension().to_lower() not in EXTENSIONS:
        failed.emit("Formato não aceito. Use PNG, JPG ou WebP.")
        return
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        failed.emit("Não foi possível ler o arquivo.")
        return
    if bytes.size() > MAX_FILE:
        failed.emit("Arquivo grande demais (máximo 12 MB).")
        return
    picked.emit(bytes, path.get_file())

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
            if (!f) { window.fraihaPickCb(['cancel', '', '']); inp.remove(); return; }
            if (f.size > %d) { window.fraihaPickCb(['error', 'Arquivo grande demais (máximo 12 MB).', '']); inp.remove(); return; }
            const r = new FileReader();
            r.onload = () => {
                const b = new Uint8Array(r.result); let s = '';
                for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
                window.fraihaPickCb(['ok', btoa(s), f.name]); inp.remove();
            };
            r.onerror = () => { window.fraihaPickCb(['error', 'Não foi possível ler o arquivo.', '']); inp.remove(); };
            r.readAsArrayBuffer(f);
        });
        inp.click();
    })()
    """ % MAX_FILE)

func _on_web_result(args: Array):
    if args.is_empty() or not (args[0] is Array): return
    var a: Array = args[0]
    var kind := String(a[0])
    if kind == "ok":
        var bytes := Marshalls.base64_to_raw(String(a[1]))
        var fname := String(a[2])
        if fname.get_extension().to_lower() not in EXTENSIONS and fname.get_extension() != "":
            failed.emit("Formato não aceito. Use PNG, JPG ou WebP.")
            return
        picked.emit(bytes, fname)
    elif kind == "error":
        failed.emit(String(a[1]))
