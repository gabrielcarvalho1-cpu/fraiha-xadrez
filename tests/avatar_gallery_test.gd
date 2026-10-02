extends SceneTree
## Galeria de avatares do Perfil (R29) + botão de som da Home.
## Desbloqueio derivado da escada de bots (bot_progress), IDs preservados, bloqueado não seleciona,
## conquistado sem arte não seleciona, selecionado destacado; som usa o bus Master e persiste nas prefs.
## Rodar: FRAIHA_SERVER_URL=ws://127.0.0.1:9 xvfb-run -a godot --path . -s tests/avatar_gallery_test.gd
const Progress = preload("res://bot/bot_progress.gd")
const Ladder = preload("res://bot/bot_ladder.gd")
const Catalog = preload("res://profile/avatar_catalog.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func frames(n := 3):
    for i in n: await process_frame

func run():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.FILE))
    # preferências limpas (guarda as do aparelho e devolve no fim)
    var prefs_path := ProjectSettings.globalize_path(preload("res://ui_v022/main_hub.gd").PREFS)
    var saved_prefs := FileAccess.get_file_as_bytes(prefs_path) if FileAccess.file_exists(prefs_path) else PackedByteArray()
    DirAccess.remove_absolute(prefs_path)
    # ---------- catálogo ----------
    var ids := Catalog.ids()
    check(Array(ids).slice(0, 4) == ["warrior", "archer", "peao_branco", "peao_negro"], "coleção começa pelos 4 avatares gratuitos (Guerreiro, Arqueira, Peão Branco, Peão Negro)")
    var rewards := []
    for id in Ladder.ids(): rewards.append(String(Ladder.reward(id).get("id", "")))
    var tail := Array(ids).slice(4, 4 + rewards.size())
    check(tail == rewards, "recompensas na ordem da escada (IDs do bot_ladder.json)")
    check(rewards[0] == "madeira_reward" and rewards[1] == "ferro_reward" and rewards[10] == "challenger_reward", "R30: 11 artes novas das ligas (Madeira → Challenger)")
    check(not ("mage" in ids) and not ("paladin" in ids), "Mago/Paladino saíram da coleção")
    check(ids[ids.size() - 4] == "fundador", "avatar Fundador depois da escada")
    check(Array(ids).slice(ids.size() - 3) == ["club_avatar_a", "club_avatar_b", "club_avatar_c"], "R31: 3 avatares do Club no fim da coleção")
    check(ids.size() == 4 + Ladder.ids().size() + 1 + 3, "todos os avatares aparecem (%d)" % ids.size())
    check(Catalog.missing_art().is_empty(), "todas as artes presentes (nenhum 'ARTE EM BREVE')")
    print("INFO arte ausente: ", Catalog.missing_art())

    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(30)
    var hub = stage.hub
    var bp = hub.bot_progress
    hub.show_page("profile")
    await frames(5)
    var g = hub.avatar_gallery
    check(g != null and g.cards.size() == ids.size(), "galeria do PC mostra todos os avatares")
    # ---------- estados iniciais ----------
    check(g.state_of("warrior") == "selected", "Guerreiro selecionado por padrão (destaque)")
    check(g.state_of("archer") == "unlocked", "Arqueira inicial liberada")
    check(g.state_of("madeira_reward") == "locked" and g.state_of("ferro_reward") == "locked", "Rei de Madeira/Torre de Ferro bloqueados sem vitórias")
    check(String(g.cards["madeira_reward"].tooltip_text).contains("BLOQUEADO") and String(g.cards["madeira_reward"].tooltip_text).contains("BOT MADEIRA"), "bloqueado: dica BLOQUEADO · Derrote o BOT MADEIRA")
    check(g.count_unlocked() == 4, "4 avatares gratuitos liberados no início")
    # ---------- bloqueado não seleciona ----------
    g.cards["madeira_reward"].pressed.emit()
    await frames(2)
    check(hub.avatar_id == "warrior", "clicar em bloqueado não troca o avatar")
    check(String(hub.inspected_avatar) == "madeira_reward", "clicar em bloqueado mostra o detalhe")
    hub.choose_avatar("madeira_reward")
    check(hub.avatar_id == "warrior", "choose_avatar recusa avatar bloqueado")
    # ---------- desbloqueio pela escada ----------
    bp._grant("madeira")
    await frames(3)
    stage.reward_modal.close()
    hub._refresh_avatars()
    await frames(2)
    check(g.state_of("madeira_reward") == "unlocked", "vencer o BOT MADEIRA libera o Rei de Madeira")
    g.cards["madeira_reward"].pressed.emit()
    await frames(2)
    check(hub.avatar_id == "warrior" and g.focus_id == "madeira_reward", "R32: tocar no avatar só o coloca em foco (não aplica)")
    check(hub.avatar_detail.apply.text == "APLICAR AVATAR" and not hub.avatar_detail.apply.disabled, "R32: botão APLICAR AVATAR habilitado para o conquistado")
    hub.avatar_detail.apply.pressed.emit()
    await frames(2)
    check(hub.avatar_id == "madeira_reward" and g.state_of("madeira_reward") == "selected" and g.state_of("warrior") == "unlocked", "APLICAR AVATAR: Rei de Madeira passa a ser o avatar em uso")
    check(hub.avatar_detail.apply.text == "EM USO" and hub.avatar_detail.apply.disabled, "depois de aplicar o botão mostra EM USO")
    # ---------- R32: ÍCONES separados ----------
    hub.set_profile_tab("icons")
    await frames(2)
    check(hub.badge_gallery != null and hub.gallery_scrolls.icons.visible and not hub.gallery_scrolls.avatars.visible, "aba ÍCONES troca a galeria (ícones separados dos avatares)")
    hub.badge_gallery.cards["fundador"].pressed.emit()
    await frames(2)
    check(hub.avatar_detail.apply.disabled and hub.avatar_detail.apply.text == "BLOQUEADO", "ícone Fundador bloqueado sem o pacote")
    hub.badge_gallery.cards[""].pressed.emit()
    await frames(1)
    check(hub.avatar_detail.apply.text == "APLICAR ÍCONE", "ícone disponível: APLICAR ÍCONE")
    hub.avatar_detail.apply.pressed.emit()
    await frames(1)
    check(hub.badge_pref == "" and hub.avatar_id == "madeira_reward", "APLICAR ÍCONE troca só o ícone (avatar continua)")
    hub.set_cosmetic("badge", "auto")
    hub.set_profile_tab("avatars")
    # ---------- conquistado sem arte ----------
    bp._grant("ferro")
    bp._grant("bronze")
    await frames(2)
    stage.reward_modal.close()
    hub._refresh_avatars()
    if not Catalog.has_art("bronze_reward"):
        check(g.state_of("bronze_reward") == "no_art_unlocked", "bronze_reward conquistado mas sem arte: estado próprio")
        hub.choose_avatar("bronze_reward")
        check(hub.avatar_id == "madeira_reward", "avatar sem arte não é selecionado")
    else:
        check(g.state_of("bronze_reward") == "unlocked", "bronze_reward com arte e liberado")
    check(g.count_unlocked() == 7, "contagem: 7 conquistados após 3 vitórias")
    check(String(hub.gallery_count.text).contains("7 de %d" % ids.size()), "texto da contagem atualizado")
    # ---------- Pacote Fundador: avatar + Selo ----------
    check(g.state_of("fundador") == "locked" and String(g.cards["fundador"].tooltip_text).contains("Pacote Fundador"), "sem Pacote Fundador: avatar Fundador bloqueado (Exclusivo do Pacote Fundador)")
    var before_f = hub.avatar_id
    hub.choose_avatar("fundador")
    check(hub.avatar_id == before_f, "sem o pacote: não seleciona o avatar Fundador")
    check(not hub.founder_row.visible and not hub.ref_founder_badge.visible, "sem o pacote: Selo Fundador escondido")
    hub.entitlements.apply_server({"is_founder": true, "club_active": false, "club_expires_at": ""})
    await frames(3)
    check(hub.is_founder() and g.state_of("fundador") == "unlocked", "Fundador (servidor is_founder): avatar liberado")
    g.cards["fundador"].pressed.emit()
    hub.avatar_detail.apply.pressed.emit()
    check(hub.avatar_id == "fundador" and hub.avatar_texture() != null, "Fundador aplica o avatar exclusivo (APLICAR AVATAR)")
    hub.show_page("main")
    await frames(3)
    hub.refresh_founder()
    check(hub.ref_founder_badge.visible, "Selo Fundador ao lado do nome na Home")
    hub.show_page("profile")
    await frames(3)
    check(hub.founder_row.visible, "Selo Fundador no Perfil")
    hub.entitlements.clear_server()
    await frames(3)
    check(not hub.is_founder() and g.state_of("fundador") == "locked" and not hub.founder_row.visible, "sem o pacote de novo: selo some e avatar bloqueia")
    check(hub.avatar_texture() == hub.avatar_texture("warrior"), "avatar Fundador sem pacote ativo é exibido como Guerreiro")
    hub.choose_avatar("madeira_reward")
    # ---------- persistência da escolha ----------
    hub._save_preferences()
    var cfg := ConfigFile.new()
    cfg.load(hub.PREFS)
    check(String(cfg.get_value("profile", "avatar", "")) == "madeira_reward", "avatar escolhido salvo nas preferências")
    # ---------- som ----------
    var before := AudioServer.is_bus_mute(0)
    hub.set_sound_muted(false)
    check(not AudioServer.is_bus_mute(0), "som ligado: Master sem mute")
    hub.toggle_sound()
    check(hub.sound_muted and AudioServer.is_bus_mute(0), "botão de som: desliga (Master mute)")
    cfg = ConfigFile.new()
    cfg.load(hub.PREFS)
    check(bool(cfg.get_value("audio", "muted", false)), "estado do som persiste (audio/muted)")
    check(hub.sound_button != null and hub.sound_button.get("glyph") == "sound_off", "ícone muda para som desligado")
    hub.toggle_sound()
    check(not hub.sound_muted and not AudioServer.is_bus_mute(0), "botão de som: liga de novo")
    check(hub.sound_button.get("glyph") == "sound_on", "ícone volta para som ligado")
    AudioServer.set_bus_mute(0, before)
    # ---------- Club no canto superior esquerdo ----------
    hub.show_page("main")
    await frames(3)
    if hub.club_entry != null:
        check(hub.club_entry.position.x < 80 and hub.club_entry.position.y < 60, "CLUB FRAIHA no canto superior esquerdo")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.FILE))
    DirAccess.remove_absolute(prefs_path)
    if not saved_prefs.is_empty():
        var f := FileAccess.open(prefs_path, FileAccess.WRITE)
        f.store_buffer(saved_prefs)
        f.close()
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
