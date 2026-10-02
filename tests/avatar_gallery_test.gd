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
    check(ids[0] == "warrior" and ids[1] == "archer", "coleção começa pelos avatares iniciais")
    var rewards := []
    for id in Ladder.ids(): rewards.append(String(Ladder.reward(id).get("id", "")))
    var tail := Array(ids).slice(2)
    check(tail == rewards, "recompensas na ordem da escada (IDs do bot_ladder.json preservados)")
    check("mage" in ids and "paladin" in ids, "IDs antigos (mage/paladin) preservados")
    check(ids.size() == 2 + Ladder.ids().size(), "todos os avatares aparecem (%d)" % ids.size())
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
    check(g.state_of("mage") == "locked" and g.state_of("paladin") == "locked", "Mago/Paladino bloqueados sem vitórias")
    check(String(g.cards["mage"].tooltip_text).contains("BLOQUEADO") and String(g.cards["mage"].tooltip_text).contains("BOT MADEIRA"), "bloqueado: dica BLOQUEADO · Derrote o BOT MADEIRA")
    check(g.count_unlocked() == 2, "2 avatares conquistados no início")
    # ---------- bloqueado não seleciona ----------
    g.cards["mage"].pressed.emit()
    await frames(2)
    check(hub.avatar_id == "warrior", "clicar em bloqueado não troca o avatar")
    check(String(hub.inspected_avatar) == "mage", "clicar em bloqueado mostra o detalhe")
    hub.choose_avatar("mage")
    check(hub.avatar_id == "warrior", "choose_avatar recusa avatar bloqueado")
    # ---------- desbloqueio pela escada ----------
    bp._grant("madeira")
    await frames(3)
    stage.reward_modal.close()
    hub._refresh_avatars()
    await frames(2)
    check(g.state_of("mage") == "unlocked", "vencer o BOT MADEIRA libera o Mago")
    g.cards["mage"].pressed.emit()
    await frames(2)
    check(hub.avatar_id == "mage" and g.state_of("mage") == "selected" and g.state_of("warrior") == "unlocked", "Mago selecionável e passa a ser o destacado")
    # ---------- conquistado sem arte ----------
    bp._grant("ferro")
    bp._grant("bronze")
    await frames(2)
    stage.reward_modal.close()
    hub._refresh_avatars()
    if not Catalog.has_art("bronze_reward"):
        check(g.state_of("bronze_reward") == "no_art_unlocked", "bronze_reward conquistado mas sem arte: estado próprio")
        hub.choose_avatar("bronze_reward")
        check(hub.avatar_id == "mage", "avatar sem arte não é selecionado")
    else:
        check(g.state_of("bronze_reward") == "unlocked", "bronze_reward com arte e liberado")
    check(g.count_unlocked() == 5, "contagem: 5 conquistados após 3 vitórias")
    check(String(hub.gallery_count.text).contains("5 de %d" % ids.size()), "texto da contagem atualizado")
    # ---------- persistência da escolha ----------
    hub._save_preferences()
    var cfg := ConfigFile.new()
    cfg.load(hub.PREFS)
    check(String(cfg.get_value("profile", "avatar", "")) == "mage", "avatar escolhido salvo nas preferências")
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
