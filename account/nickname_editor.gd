extends VBoxContainer
## Editor do NOME PÚBLICO da conta (único no FRAIHA, troca a cada 30 dias).
## Verifica disponibilidade no servidor enquanto digita; o cooldown vem do servidor
## (nickname_next_change_at), nunca do relógio local. Para convidado/sem conta, só convida a entrar.
const GOLD := Color("f1d58a")
const MUTED := Color("c9c2a8")
const OK := Color("8fe08a")
const BAD := Color("ff9d86")
const CHECK_DELAY := 0.45

var account
var input: LineEdit
var status: Label
var save_button: Button
var cooldown: Label
var hint: Label
var title: Label
var guest_note: Label
var checked_name := ""
var checked_ok := false
var check_timer: Timer
var font_size := 18

func setup(account_service, fs := 18):
    account = account_service
    font_size = fs
    name = "NicknameEditor"
    add_theme_constant_override("separation", 6)
    title = _label("SEU NOME PÚBLICO", fs + 2, GOLD)
    guest_note = _label("Entre na sua conta para escolher um nome público único no FRAIHA.", fs - 2, MUTED)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    add_child(row)
    input = LineEdit.new()
    input.name = "NicknameInput"
    input.max_length = 20
    input.placeholder_text = "Seu nome"
    input.custom_minimum_size.y = 44
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    input.add_theme_font_size_override("font_size", fs + 2)
    input.text_changed.connect(_on_text)
    input.text_submitted.connect(func(_t): _save())
    row.add_child(input)
    save_button = Button.new()
    save_button.name = "NicknameSave"
    save_button.text = "SALVAR NOME"
    save_button.custom_minimum_size = Vector2(0, 44)
    save_button.add_theme_font_size_override("font_size", fs - 2)
    save_button.disabled = true
    save_button.pressed.connect(_save)
    row.add_child(save_button)
    status = _label("", fs - 1, MUTED)
    status.name = "NicknameStatus"
    hint = _label("Único no FRAIHA · 3 a 20 caracteres · letras, números e _ · pode ser trocado a cada 30 dias.", fs - 4, MUTED)
    cooldown = _label("", fs - 2, GOLD)
    cooldown.name = "NicknameCooldown"
    check_timer = Timer.new()
    check_timer.one_shot = true
    check_timer.wait_time = CHECK_DELAY
    check_timer.timeout.connect(_check_now)
    add_child(check_timer)
    account.nickname_checked.connect(_on_checked)
    account.nickname_changed.connect(_on_changed)
    account.nickname_failed.connect(_on_failed)
    account.changed.connect(refresh)
    refresh()

func _label(text: String, fs: int, color: Color) -> Label:
    var l := Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    l.add_theme_font_size_override("font_size", fs)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    l.add_theme_constant_override("shadow_offset_y", 1)
    add_child(l)
    return l

## Estado atual da conta → campos.
func refresh():
    var logged: bool = account != null and account.has_profile()
    for n in [input.get_parent(), status, hint, cooldown]: n.visible = logged
    guest_note.visible = not logged
    if not logged: return
    if not input.has_focus(): input.text = account.nickname()
    var next_at: String = account.nickname_next_change_at()
    var locked := _in_future(next_at)
    input.editable = not locked
    save_button.visible = not locked
    cooldown.visible = locked
    if locked:
        cooldown.text = "PRÓXIMA ALTERAÇÃO DISPONÍVEL EM: " + format_date(next_at)
        status.text = "Nome atual: " + account.nickname()
        status.add_theme_color_override("font_color", MUTED)
    elif input.text == account.nickname():
        status.text = "Este é o seu nome atual."
        status.add_theme_color_override("font_color", MUTED)
        save_button.disabled = true

func _on_text(value: String):
    checked_ok = false
    save_button.disabled = true
    var clean: String = account.clean_nickname(value)
    if clean == account.nickname():
        status.text = "Este é o seu nome atual."
        status.add_theme_color_override("font_color", MUTED)
        check_timer.stop()
        return
    var err: String = account.nickname_error(value)
    if not err.is_empty():
        status.text = "X  " + err
        status.add_theme_color_override("font_color", BAD)
        check_timer.stop()
        return
    status.text = "Verificando…"
    status.add_theme_color_override("font_color", MUTED)
    check_timer.start()

func _check_now():
    if account.nickname_error(input.text).is_empty():
        account.check_nickname(input.text)

func _on_checked(nick: String, available: bool, error: String):
    if account.clean_nickname(input.text).to_lower() != nick.to_lower(): return
    checked_name = nick
    checked_ok = available
    status.text = ("OK  NOME DISPONÍVEL" if available else "X  ESSE NOME JÁ ESTÁ SENDO USADO") if error.is_empty() or available else "X  " + error
    if not available and error.begins_with("Esse nome"): status.text = "X  ESSE NOME JÁ ESTÁ SENDO USADO"
    status.add_theme_color_override("font_color", OK if available else BAD)
    save_button.disabled = not available

func _save():
    if not checked_ok or save_button.disabled: return
    save_button.disabled = true
    status.text = "Salvando…"
    account.change_nickname(input.text)

func _on_changed(nick: String, next_at: String):
    input.text = nick
    status.text = "OK  Nome salvo: " + nick
    status.add_theme_color_override("font_color", OK)
    refresh()

func _on_failed(code: String, message: String, next_at: String):
    status.text = "X  " + message
    status.add_theme_color_override("font_color", BAD)
    if code == "nickname_cooldown" and not next_at.is_empty():
        cooldown.text = "PRÓXIMA ALTERAÇÃO DISPONÍVEL EM: " + format_date(next_at)
        cooldown.visible = true
    save_button.disabled = true

## ISO 8601 (UTC) → dd/mm/aaaa (local). Só exibição; a regra é do servidor.
static func format_date(iso: String) -> String:
    if iso.is_empty(): return ""
    var unix := Time.get_unix_time_from_datetime_string(iso)
    if unix <= 0: return iso.left(10)
    var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
    return "%02d/%02d/%04d" % [int(d.day), int(d.month), int(d.year)]

static func _in_future(iso: String) -> bool:
    if iso.is_empty(): return false
    var unix := Time.get_unix_time_from_datetime_string(iso)
    return unix > 0 and unix > Time.get_unix_time_from_system()
