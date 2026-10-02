extends SceneTree
## R31 · Benefícios reais do Pacote Fundador e do Club FRAIHA:
## universos/peças exclusivos, avatares Club, ÍCONE (escolha), título, moldura, Personalização,
## LABORATÓRIO, MEU CLUB (relatório semanal, estatísticas, desafios, treinos, histórico) e
## sincronização com a conta só pelos direitos REAIS (simulação nunca vai para o servidor).
## Rodar: FRAIHA_SERVER_URL=ws://127.0.0.1:9 xvfb-run -a godot --path . -s tests/premium_r31_test.gd
const Cosmetics = preload("res://profile/premium_cosmetics.gd")
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const Insights = preload("res://analysis/club_insights.gd")
const MatchRecord = preload("res://analysis/match_record.gd")
const Catalog = preload("res://monetization/monetization_catalog.gd")
const BACKUP := ["user://home_preferences.cfg", "user://visual_theme.cfg", "user://dev_monetization_mock.cfg", "user://club_progress.cfg"]
var checks := 0
var failures := 0
var hub
var stage
var saved := {}

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func frames(n := 3):
    for i in n: await process_frame

func pnode(n: String) -> Node:
    return hub.premium.root.find_child(n, true, false) if hub.premium != null else null

func press(n: String) -> bool:
    var b = pnode(n)
    if b == null or not (b is BaseButton) or b.disabled: return false
    b.pressed.emit()
    return true

func ent(founder: bool, club: bool):
    hub.entitlements.apply_server({"is_founder": founder, "club_active": club, "club_expires_at": "2099-01-01T00:00:00Z" if club else ""})

func run():
    for p in BACKUP:
        var g := ProjectSettings.globalize_path(p)
        saved[p] = FileAccess.get_file_as_bytes(g) if FileAccess.file_exists(g) else PackedByteArray()
        DirAccess.remove_absolute(g)
    root.size = Vector2i(1600, 900)
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(20)
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    hub = stage.hub
    var tm = stage.theme_manager
    hub.monetization_state.mock_reset()
    hub.entitlements.clear_server()
    await frames(3)
    # servidor manda club_expires_at = null para quem não tem Club (antes quebrava o apply_server)
    hub.entitlements.apply_server({"is_founder": true, "club_active": false, "club_expires_at": null})
    check(hub.is_founder() and hub.entitlements.club_expires_at() == "", "Fundador do servidor com club_expires_at null é aplicado")
    hub.entitlements.clear_server()
    # ---------- catálogo / universos ----------
    check(ThemeCatalog.exclusive_of("fundador") == "founder" and ThemeCatalog.exclusive_of("club") == "club" and ThemeCatalog.exclusive_of("ouro") == "", "universos exclusivos fora das ligas")
    check(ThemeCatalog.piece_textures("fundador").size() == 12 and ThemeCatalog.piece_textures("club").size() == 12, "peças Fundador e Club: 12 sprites cada")
    check(ThemeCatalog.texture(ThemeCatalog.get_theme("fundador").arena_path) != null and ThemeCatalog.texture(ThemeCatalog.get_theme("club").arena_path) != null, "cenários Fundador e Club carregam")
    check(not tm.is_unlocked("fundador") and not tm.is_unlocked("club"), "sem direitos: universos exclusivos bloqueados")
    check(not tm.choose_theme("fundador", true) and tm.active_theme == "wood", "sem pacote: não aplica o Universo Fundador")
    ent(true, false)
    await frames(2)
    check(tm.is_unlocked("fundador") and not tm.is_unlocked("club"), "Fundador libera o Universo Fundador (não o do Club)")
    check(tm.choose_theme("fundador", true) and tm.active_theme == "fundador" and stage.game.visual_theme == "fundador", "Universo Fundador aplicado (cenário + tabuleiro)")
    check(tm.active_piece_set == "fundador", "peças acompanham o universo")
    check(not tm.choose_piece_set("club"), "peças do Club bloqueadas sem Club")
    ent(true, true)
    await frames(2)
    check(tm.choose_piece_set("club") and tm.active_piece_set == "club" and tm.active_theme == "fundador", "Club: combina peças Club com o Universo Fundador")
    var vc := ConfigFile.new()
    vc.load("user://visual_theme.cfg")
    check(String(vc.get_value("visual", "theme", "")) == "fundador" and String(vc.get_value("visual", "pieces", "")) == "club", "escolha de universo e peças persistida")
    check(tm.choose_piece_set("gold") == false, "peças de liga não conquistada continuam bloqueadas")
    hub.entitlements.clear_server()
    await frames(3)
    check(tm.active_theme == "wood" and tm.active_piece_set != "club", "direitos saem: volta para Madeira sem peças exclusivas")
    vc.load("user://visual_theme.cfg")
    check(String(vc.get_value("visual", "theme", "")) == "fundador", "preferência guardada para quando o direito voltar")
    ent(true, true)
    await frames(3)
    check(tm.active_theme == "fundador" and tm.active_piece_set == "club", "direitos voltam: universo e peças restaurados")
    tm.choose_theme("wood")
    check(tm.saved_piece_set == "" and tm.active_piece_set == "wood", "Ligas: escolher cenário volta as peças a acompanhar o cenário")
    # ---------- avatares Club ----------
    hub.entitlements.clear_server()
    await frames(2)
    check(not hub.avatar_unlocked("club_avatar_a"), "avatar Club bloqueado sem Club")
    hub.choose_avatar("club_avatar_b")
    check(hub.avatar_id != "club_avatar_b", "não seleciona avatar Club sem Club")
    ent(false, true)
    await frames(2)
    hub.choose_avatar("club_avatar_b")
    check(hub.avatar_id == "club_avatar_b" and hub.avatar_texture() == hub.avatar_texture("club_avatar_b"), "Club: seleciona o avatar Bispo Estrategista")
    # ---------- ÍCONE / TÍTULO / MOLDURA ----------
    hub.entitlements.clear_server()
    await frames(2)
    check(hub.current_badge() == "" and hub.current_title() == "" and hub.current_frame() == "liga", "sem direitos: sem ícone/título, moldura da liga")
    check(hub.avatar_texture() == hub.avatar_texture("warrior"), "avatar Club sem Club ativo aparece como Guerreiro")
    check(not hub.set_cosmetic("badge", "fundador") and not hub.set_cosmetic("badge", "club_a"), "ícones exclusivos não podem ser escolhidos sem o direito")
    ent(true, false)
    await frames(2)
    check(hub.current_badge() == "fundador" and hub.current_title() == "fundador" and hub.current_frame() == "fundador", "Fundador (automático): Selo, título e moldura Fundador")
    hub.show_page("profile")
    await frames(3)
    check(hub.founder_row.visible and hub.founder_title_label.text == "FUNDADOR DO REINO", "Perfil: título exclusivo FUNDADOR DO REINO")
    var host = hub.ref_profile_club_host if hub.ref_mode else hub.profile_portrait
    var pf = host.get_node_or_null("ClubFrame")
    check(pf != null and pf.visible and pf.style == "fundador", "moldura Fundador no retrato do jogador (Home)")
    ent(true, true)
    await frames(2)
    check(hub.set_cosmetic("badge", "club_c") and hub.current_badge() == "club_c", "jogador ESCOLHE o ícone (Club · Cavalo)")
    check(hub.set_cosmetic("frame", "club") and hub.current_frame() == "club", "jogador escolhe a moldura Club")
    check(hub.set_cosmetic("title", "club") and hub.founder_title_label.text == "MEMBRO DO CLUB FRAIHA", "jogador escolhe o título do Club")
    hub.show_page("main")
    await frames(3)
    hub.refresh_founder()
    check(hub.ref_founder_badge.texture == Cosmetics.badge_texture("club_c"), "Home: ícone escolhido ao lado do nome")
    var cfg := ConfigFile.new()
    cfg.load(hub.PREFS)
    check(String(cfg.get_value("profile", "badge", "")) == "club_c" and String(cfg.get_value("profile", "frame", "")) == "club", "escolhas salvas nas preferências")
    ent(true, false)
    await frames(2)
    check(hub.current_badge() == "" and hub.current_frame() == "liga", "Club vence: ícone/moldura do Club somem (escolha mantida)")
    check(hub.set_cosmetic("badge", "auto") and hub.current_badge() == "fundador", "AUTOMÁTICO volta ao Selo Fundador")
    hub.set_cosmetic("title", "auto")
    hub.set_cosmetic("frame", "auto")
    # simulação nunca vai para a conta
    hub.entitlements.clear_server()
    hub.monetization_state.mock_activate_founder()
    await frames(2)
    check(hub.is_founder() and hub.current_badge() == "fundador", "simulação Fundador mostra o selo localmente")
    check(hub.public_cosmetics().badge == "" and hub.public_cosmetics().frame == "liga", "simulação NÃO é enviada à conta (só direitos reais)")
    hub.monetization_state.mock_reset()
    # ---------- Personalização ----------
    ent(true, false)
    await frames(2)
    hub.open_premium("personalize")
    await frames(4)
    check(hub.premium.visible and hub.premium.page == "personalize", "Personalização abre (ícone, título, moldura, universo, peças)")
    for n in ["PersonalizeBadges", "PersonalizeTitles", "PersonalizeFrames", "PersonalizeUniverses", "PersonalizePieces", "PersonalizeLab"]:
        check(pnode(n) != null, "seção " + n)
    check(pnode("Badge_club_a") != null and bool(pnode("Badge_club_a").get_meta("locked")), "ícone Club bloqueado (cinza) sem Club")
    check(press("Badge_fundador") and hub.badge_pref == "fundador", "tocar no ícone Fundador escolhe")
    await frames(2)
    check(bool(pnode("Badge_fundador").get_meta("selected")), "ícone escolhido marcado EM USO")
    check(press("Universe_fundador") and tm.active_theme == "fundador", "Personalização aplica o Universo Fundador")
    await frames(2)
    check(press("LabCoordinates") and stage.game.show_coordinates, "LABORATÓRIO: coordenadas no tabuleiro (acesso antecipado)")
    await frames(2)
    press("LabCoordinates")
    await frames(2)
    check(not stage.game.show_coordinates, "LABORATÓRIO: desliga")
    hub.premium.back()
    await frames(2)
    check(not hub.premium.visible, "VOLTAR na Personalização (aberta do Perfil) fecha")
    tm.choose_theme("wood")
    # ---------- histórico real + MEU CLUB ----------
    var hist = stage.analysis_history
    hist.file = "user://test_r31_history.json"
    hist.reports_dir = "user://test_r31_reports/"
    hist.entries = []
    var rec = MatchRecord.new()
    rec.start("bot", "w", "Eu", "BOT MADEIRA")
    for u in ["f2f3", "e7e5", "g2g4", "d8h4"]: rec.add_move(u)
    rec.finish("loss", "mate")
    var eng = stage.analysis_engine
    if not eng.engine_ready: await eng.start()
    var an = preload("res://analysis/analyzer.gd").new(eng)
    stage.add_child(an)
    an.depth = 6
    an.max_ms_per_pos = 400
    var rep: Dictionary = await an.analyze(rec)
    check(rep.moves.size() == 4, "análise real da partida de teste (%s)" % eng.engine_name)
    hist.record(rec, rep)
    check(hist.entries.size() == 1 and hist.has_report(hist.entries[0]), "histórico guarda o relatório completo")
    var e0: Dictionary = hist.entries[0]
    check(e0.has("phases") and e0.opponent == "BOT MADEIRA" and int(e0.plies) == 4, "resumo com fases, adversário e lances")
    var mist: Array = hist.mistakes(10)
    check(mist.size() >= 1 and String(mist[0].color) == "w" and mist[0].has("fen_before") and int(mist[0].move_no) >= 1, "erros do histórico viram exercícios (%d)" % mist.size())
    check(not hist.load_report(e0).is_empty(), "relatório completo recarregado")
    hub.entitlements.clear_server()
    await frames(2)
    hub.open_premium("myclub")
    await frames(4)
    check(pnode("MyClubLocked") != null and pnode("AdvancedStats") == null, "MEU CLUB exclusivo do Club (sem Club: convite)")
    ent(false, true)
    await frames(2)
    hub.premium.show_page("myclub")
    await frames(4)
    for n in ["WeeklyReport", "AdvancedStats", "ClubChallenges", "ClubTraining", "ClubHistory", "HistoryRow1"]:
        check(pnode(n) != null, "MEU CLUB: " + n)
    check(pnode("WeeklyChart") != null and pnode("WeeklyChart").vals[0] + pnode("WeeklyChart").vals[1] + pnode("WeeklyChart").vals[2] + pnode("WeeklyChart").vals[3] + pnode("WeeklyChart").vals[4] + pnode("WeeklyChart").vals[5] + pnode("WeeklyChart").vals[6] == 1, "relatório semanal com a partida real da semana")
    var review = pnode("HistoryRow1").find_child("Review", true, false)
    check(review != null and not review.disabled, "histórico: REVER ANÁLISE disponível")
    review.pressed.emit()
    await frames(3)
    check(stage.analysis_ui != null and stage.analysis_ui.visible and stage.analysis_ui.page == "report", "REVER reabre a análise guardada (sem gastar cota)")
    stage.analysis_ui.close()
    var go = pnode("TrainMistakes").find_child("Go", true, false)
    check(go != null and not go.disabled, "TREINE MEUS ERROS habilitado")
    go.pressed.emit()
    await frames(3)
    check(stage.training_ui != null and stage.training_ui.visible and stage.training_ui.exercises.size() >= 1, "treino com posições do histórico")
    stage.training_ui.close()
    hub.premium.show_page("club")
    await frames(4)
    check(pnode("WeeklyReport") != null and pnode("WeeklyChart") != null and pnode("ClubOpenMyClub") != null, "página do Club (membro): relatório REAL + ABRIR MEU CLUB")
    hub.premium.close()
    # ---------- insights (unidade) ----------
    var now := 1790000000
    var ws := Insights.week_start(now)
    var fake := [
        {"played_at": ws + 3600, "accuracy": 85.0, "result": "win", "mode": "bot", "color": "w", "counts": {"blunder": 0, "mistake": 1}, "phases": {"opening": 0, "middle": 1, "end": 0}, "plies": 40},
        {"played_at": ws + 90000, "accuracy": 60.0, "result": "win", "mode": "ranked", "color": "b", "counts": {"blunder": 2}, "phases": {"opening": 0, "middle": 0, "end": 2}, "plies": 30},
        {"played_at": ws - 3600, "accuracy": 50.0, "result": "loss", "mode": "bot", "color": "w", "counts": {"blunder": 1}, "phases": {"opening": 1, "middle": 0, "end": 0}, "plies": 30},
    ]
    var s := Insights.stats(fake)
    check(s.games == 3 and s.wins == 2 and s.streak == 2 and absf(s.accuracy - 65.0) < 0.01 and s.weakest_phase == "end", "estatísticas: precisão, sequência e fase mais fraca")
    var w := Insights.weekly(fake, now)
    check(w.games == 2 and w.prev_games == 1 and w.days[0] == 1 and w.days[1] == 1 and w.focus_phase == "end", "relatório semanal: semana atual vs. anterior")
    var ch := Insights.challenges(fake, now, 5)
    var done := 0
    for c in ch:
        if c.done: done += 1
    check(ch.size() == 5 and done == 4, "desafios da semana acompanhados (4 de 5 sem o 'Analista')")
    # ---------- textos dos pacotes ----------
    check(Catalog.FOUNDER_WHATSAPP_URL == "https://chat.whatsapp.com/DAsWxKiLOO8F37YJGSwhLc", "WhatsApp dos Fundadores configurado")
    var soon := 0
    for b in preload("res://monetization/club_ui.gd").BENEFITS:
        if b[3] != "DISPONÍVEL": soon += 1
    check(soon == 1, "Club: só o desconto da loja segue EM BREVE")
    var fsoon := 0
    for b in preload("res://monetization/founder_ui.gd").BENEFITS:
        if b[3] == "soon": fsoon += 1
    check(fsoon == 0, "Fundador: todos os benefícios liberados")
    # ---------- limpeza ----------
    for f in ["user://test_r31_history.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
    for e in hist.entries:
        if String(e.get("report_file", "")) != "": DirAccess.remove_absolute(ProjectSettings.globalize_path(hist.reports_dir + String(e.report_file)))
    hub.entitlements.clear_server()
    for p in BACKUP:
        var g := ProjectSettings.globalize_path(p)
        DirAccess.remove_absolute(g)
        if not saved[p].is_empty():
            var f := FileAccess.open(g, FileAccess.WRITE)
            f.store_buffer(saved[p])
            f.close()
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
