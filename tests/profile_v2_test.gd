extends SceneTree
## Perfil V2: nome público (regras, editor, disponibilidade, troca, cooldown) e foto
## (decodificação, EXIF, editor de enquadramento, 512x512, cache local, upload).
## Parte offline sempre roda; a parte com servidor usa /tmp/run_account_session.sh-like:
##   FRAIHA_SERVER_URL=ws://127.0.0.1:PORT (servidor FRAIHA_DEV_AUTH=1) — se não houver, pula.
const Store := preload("res://profile/avatar_store.gd")
const Editor := preload("res://profile/avatar_editor.gd")
const Account := preload("res://account/account_service.gd")
var failures = 0
var checks = 0
func check(ok: bool, label: String):
    checks += 1
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()

func sample(w: int, h: int) -> Image:
    var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
    for y in h:
        for x in w:
            img.set_pixel(x, y, Color(float(x) / w, float(y) / h, 0.3, 1.0))
    return img

func run():
    var mobile := "--mobile-test" in OS.get_cmdline_user_args()
    root.size = Vector2i(390, 844) if mobile else Vector2i(1920, 1080)
    root.content_scale_size = root.size
    await process_frame
    # ---------------- regras do nome (cliente = servidor)
    check(Account.nickname_error("Gabriel").is_empty() and Account.nickname_error("Gabriel_01").is_empty(), "nome válido")
    check(not Account.nickname_error("ab").is_empty() and not Account.nickname_error("a".repeat(21)).is_empty(), "3 a 20 caracteres")
    check(not Account.nickname_error("Ga briel").is_empty() and not Account.nickname_error("Gabriél").is_empty(), "espaço/acento recusados")
    check(Account.clean_nickname("  Gab" + char(0x200B) + "riel" + char(0x202E) + "  ") == "Gabriel", "invisíveis/bidi/espaços nas pontas removidos")
    check(not Account.nickname_error(char(0x200B) + char(0x200B) + char(0x200B)).is_empty(), "só invisíveis = vazio")
    check(preload("res://account/nickname_editor.gd").format_date("2026-10-31T12:00:00Z").ends_with("/2026"), "data do cooldown formatada dd/mm/aaaa")

    # ---------------- decodificação + EXIF
    var src := sample(800, 600)
    var png := src.save_png_to_buffer()
    var jpg := src.save_jpg_to_buffer(0.9)
    var webp := src.save_webp_to_buffer(true, 0.9)
    check(Store.sniff(png) == "png" and Store.sniff(jpg) == "jpg" and Store.sniff(webp) == "webp" and Store.sniff("abc".to_utf8_buffer()) == "", "assinatura PNG/JPG/WebP")
    check(Store.decode(png) != null and Store.decode(jpg) != null and Store.decode(webp) != null and Store.decode("abc".to_utf8_buffer()) == null, "decodifica os três formatos e recusa lixo")
    # EXIF orientação 6 (rotacionar 90°): JPEG com segmento APP1 artesanal
    var exif := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x1E, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, 0x01, 0x00, 0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00])
    exif.append_array(jpg.slice(2))
    check(Store.exif_orientation(exif) == 6 and Store.exif_orientation(jpg) == 1, "lê a orientação EXIF")
    var rotated := Store.decode(exif)
    check(rotated != null and rotated.get_width() == 600 and rotated.get_height() == 800, "orientação EXIF 6 corrige (gira 90°)")

    # ---------------- editor: enquadrar, zoom, mover, salvar 512x512
    var editor := Editor.new()
    root.add_child(editor)
    await process_frame
    check(editor.open_with("abc".to_utf8_buffer()) != "" and not editor.visible, "arquivo inválido: mensagem e editor fechado")
    check(editor.open_with(sample(30, 30).save_png_to_buffer()) != "", "imagem pequena demais recusada")
    var huge := sample(5000, 2500).save_png_to_buffer()
    check(editor.open_with(huge) == "" and editor.source.get_width() <= 2048, "foto enorme é reduzida antes de editar")
    check(editor.open_with(png) == "" and editor.visible, "abre com PNG válido")
    var r0: Rect2 = editor._photo_rect()
    check(absf(r0.size.y - editor.preview_size) < 1.0 and r0.size.x > r0.size.y, "zoom 1: a foto cobre o quadrado pelo menor lado")
    editor.set_zoom(2.0)
    var r1: Rect2 = editor._photo_rect()
    check(absf(r1.size.y - editor.preview_size * 2.0) < 1.0, "zoom 2x dobra a foto")
    editor.pan = Vector2(-9999, 0)
    var r2: Rect2 = editor._photo_rect()
    check(r2.end.x >= editor.preview_size - 0.5 and r2.position.x <= 0.5, "mover nunca deixa borda vazia no quadrado")
    editor.set_zoom(1.0)
    editor.pan = Vector2.ZERO
    var got := {}
    editor.saved.connect(func(img, bytes):
        got["img"] = img
        got["bytes"] = bytes)
    editor._save()
    check(got.has("img") and got.img.get_width() == 512 and got.img.get_height() == 512, "salvar gera 512x512")
    check(got.has("bytes") and got.bytes.size() > 0 and got.bytes.size() <= 400 * 1024 and Store.sniff(got.bytes) == "webp", "bytes WebP ≤ 400 KB")
    check(not editor.visible, "editor fecha ao salvar")
    # cancelar
    editor.open_with(png)
    var cancelled := [false]
    editor.cancelled.connect(func(): cancelled[0] = true)
    editor.root.find_child("AvatarCancel", true, false).pressed.emit()
    check(cancelled[0] and not editor.visible, "cancelar fecha sem salvar")
    # ---------------- cache local
    var store := Store.new()
    root.add_child(store)
    store.clear_local("teste")
    check(not store.has_local("teste"), "cache começa vazio")
    var bytes := store.save_local("teste", got.img)
    check(store.has_local("teste") and store.texture_for("teste") != null and bytes.size() > 0, "salva no cache local")
    var store2 := Store.new()
    root.add_child(store2)
    check(store2.texture_for("teste") != null, "foto persiste ao recarregar (novo store lê o arquivo)")
    store.clear_local("teste")
    check(not store2.has_local("teste") or store.texture_for("teste") == null, "remover apaga o arquivo")

    # ---------------- Home: página Perfil com os controles
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 6: await process_frame
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    var hub = stage.hub
    hub.show_page("profile")
    for i in 3: await process_frame
    check(hub.find_child("ChangePhoto", true, false) != null and hub.find_child("RemovePhoto", true, false) != null, "Perfil tem ALTERAR FOTO / REMOVER FOTO")
    var ed = hub.find_child("NicknameEditor", true, false)
    check(ed != null, "Perfil tem o editor de nome público")
    check(ed != null and ed.guest_note.visible and not ed.input.get_parent().visible, "sem conta: convite para entrar, sem campo de nome público")
    check(hub.find_child("LocalNameBox", true, false) == null or hub.find_child("LocalNameBox", true, false).visible or mobile, "sem conta: nome local disponível")
    # foto própria sem conta: chave "local"
    hub.avatar_store.clear_local("local")
    hub._on_photo_saved(got.img, got.bytes)
    check(hub.custom_avatar() != null and hub.avatar_texture() == hub.custom_avatar(), "foto salva vira o avatar da Home")
    hub.remove_custom_avatar()
    check(hub.custom_avatar() == null, "remover foto volta ao avatar padrão")

    # ---------------- servidor (dev) — nome público real e upload
    var url := OS.get_environment("FRAIHA_SERVER_URL")
    if url.begins_with("ws://127.0.0.1") and not url.ends_with(":9"):
        var acc = stage.account
        acc.access_token = "dev:PerfilV2"
        acc.user_id = "perfilv2"
        acc.email = "perfil@dev.local"
        acc._server_auth()
        check(await wait_until(func(): return acc.server_ready, 8.0), "servidor dev: acct_state")
        if acc.needs_nickname: acc.create_profile("PerfilV2")
        check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil criado")
        for i in 3: await process_frame
        check(ed.input.get_parent().visible and ed.input.text == "PerfilV2" and not ed.guest_note.visible, "com conta: editor mostra o nome atual")
        check(hub.player_name == "PerfilV2", "nome público vira o nome da Home")
        var results := []
        acc.nickname_checked.connect(func(n, a, e): results.append([n, a, e]))
        ed.input.text = "PerfilV2_Novo"
        ed._on_text(ed.input.text)
        check(await wait_until(func(): return results.size() > 0, 5.0) and results[0][1] == true and ed.status.text == "✓ NOME DISPONÍVEL", "verificação: ✓ NOME DISPONÍVEL")
        check(not ed.save_button.disabled, "SALVAR NOME habilitado quando disponível")
        # segundo jogador com o nome que vamos tentar
        var other = Account.new()
        root.add_child(other)
        other.server_url = url
        other.access_token = "dev:Outro2"
        other.user_id = "outro2"
        other.email = "outro2@dev.local"
        other._server_auth()
        check(await wait_until(func(): return other.server_ready, 8.0), "segundo jogador conecta")
        if other.needs_nickname: other.create_profile("Ocupado")
        check(await wait_until(func(): return other.has_profile(), 6.0), "segundo jogador tem perfil 'Ocupado'")
        results.clear()
        ed.input.text = "OCUPADO"
        ed._on_text(ed.input.text)
        check(await wait_until(func(): return results.size() > 0, 5.0) and results[0][1] == false and "JÁ ESTÁ SENDO USADO" in ed.status.text, "verificação: ✕ ESSE NOME JÁ ESTÁ SENDO USADO (case-insensitive)")
        check(ed.save_button.disabled, "SALVAR NOME desabilitado quando usado")
        ed.input.text = "ab"
        ed._on_text(ed.input.text)
        check(ed.status.text.begins_with("✕"), "inválido: mensagem local imediata")
        # troca real
        results.clear()
        ed.input.text = "PerfilV2_Novo"
        ed._on_text(ed.input.text)
        await wait_until(func(): return results.size() > 0, 5.0)
        var changed := []
        acc.nickname_changed.connect(func(n, next): changed.append([n, next]))
        ed._save()
        check(await wait_until(func(): return changed.size() > 0, 6.0) and changed[0][0] == "PerfilV2_Novo" and changed[0][1] != "", "troca de nome salva; servidor informa a próxima data")
        check(await wait_until(func(): return acc.nickname() == "PerfilV2_Novo" and hub.player_name == "PerfilV2_Novo", 5.0), "nome novo em toda a interface")
        for i in 3: await process_frame
        check(ed.cooldown.visible and ed.cooldown.text.begins_with("PRÓXIMA ALTERAÇÃO DISPONÍVEL EM: ") and not ed.input.editable, "cooldown de 30 dias exibido com a data do servidor")
        var failed := []
        acc.nickname_failed.connect(func(c, m, n): failed.append(c))
        acc.change_nickname("PerfilV2_Outro")
        check(await wait_until(func(): return failed.size() > 0, 5.0) and failed[0] == "nickname_cooldown", "segunda troca recusada pelo servidor (cooldown)")
        # perfil público do outro jogador: nick e sem e-mail
        var seen := []
        other.server_message.connect(func(m): seen.append(m))
        other.send_server({"type": "social_search", "query": "Perfil"})
        check(await wait_until(func(): return seen.any(func(m): return String(m.get("type", "")) == "social_search"), 5.0), "pesquisa de jogador responde")
        var found = seen.filter(func(m): return String(m.get("type", "")) == "social_search")
        var txt := JSON.stringify(found[0]) if found.size() > 0 else ""
        check("PerfilV2_Novo" in txt and "@" not in txt, "perfil público mostra o nick novo e nunca o e-mail")
        # upload do avatar pela conta
        var saved_urls := []
        acc.avatar_saved.connect(func(u): saved_urls.append(u))
        hub._on_photo_saved(got.img, got.bytes)
        check(await wait_until(func(): return saved_urls.size() > 0, 6.0) and saved_urls[0] != "", "upload da foto aceito pelo servidor (avatar_url)")
        check(await wait_until(func(): return acc.avatar_url() != "", 5.0), "acct_state traz avatar_url")
        check(hub.avatar_key() == acc.user_id and hub.custom_avatar() != null, "cache local usa a chave da conta")
        hub.remove_custom_avatar()
        check(await wait_until(func(): return saved_urls.size() > 1 and saved_urls[1] == "", 6.0), "remover foto limpa no servidor")
        acc.sign_out()
        other.sign_out()
    else:
        print("SKIP servidor dev não configurado (FRAIHA_SERVER_URL)")
    print("PROFILE_V2_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit()
