extends SceneTree
## Desafio das Ligas: escada, perfis Stockfish, camada de erro, progresso/recompensas,
## fair play (nenhuma engine em partida humana) e instâncias separadas (análise × bot).
## Com FRAIHA_STOCKFISH apontando para um Stockfish, também testa o motor de verdade.
const Ladder = preload("res://bot/bot_ladder.gd")
const Progress = preload("res://bot/bot_progress.gd")
const FairPlay = preload("res://analysis/fair_play.gd")
const EngineScript = preload("res://analysis/engine.gd")
const LeagueCatalog = preload("res://league/catalog.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

class StubGame extends Node2D:
    var game_over := false
class StubStage extends Node:
    var mode := "home"
    var game := StubGame.new()
    var ranked = null
    var casual = null

func _init():
    _run.call_deferred()

func _run():
    # ---------- escada ----------
    check(Ladder.ids() == PackedStringArray(LeagueCatalog.IDS), "11 bots na ordem real das ligas do projeto")
    var o := Ladder.uci_options("madeira")
    check(o["Skill Level"] == 0 and o["UCI_LimitStrength"] == "false" and o["MultiPV"] == 5, "MADEIRA: Skill Level 0, sem LimitStrength, MultiPV 5")
    var g := Ladder.uci_options("ouro")
    check(g["UCI_LimitStrength"] == "true" and int(g["UCI_Elo"]) >= 1320 and g["Skill Level"] == 20, "OURO: UCI_LimitStrength + UCI_Elo")
    check(Ladder.go_command("madeira") == "go depth 1" and Ladder.go_command("challenger").begins_with("go movetime"), "limite por lance de cada perfil (depth / movetime)")
    var prev := 0
    var mono := true
    for id in ["ouro","platina","esmeralda","diamante","mestre","grande_mestre"]:
        var e := int(Ladder.uci_options(id)["UCI_Elo"])
        if e <= prev: mono = false
        prev = e
    check(mono, "UCI_Elo cresce de OURO a GRANDE MESTRE")
    var c := Ladder.uci_options("challenger")
    check(c["UCI_LimitStrength"] == "false" and c["Skill Level"] == 20, "CHALLENGER: força total")
    # camada de erro
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var fake := {"bestmove": "e2e4", "lines": {1: {"cp": 50, "mate": 0, "move": "e2e4"}, 2: {"cp": 20, "mate": 0, "move": "d2d4"}, 3: {"cp": -900, "mate": 0, "move": "g1h3"}}}
    var kinds := {}
    var bad := 0
    for i in 400:
        var p := Ladder.pick("ferro", fake, PackedStringArray(["e2e4","d2d4","g1h3","a2a3"]), rng)
        kinds[p.kind] = int(kinds.get(p.kind, 0)) + 1
        if p.kind == "suboptimal" and p.move == "g1h3": bad += 1
    check(kinds.has("engine") and kinds.has("suboptimal") and kinds.has("random"), "FERRO mistura lance do Stockfish, subótimo e aleatório")
    check(bad == 0, "subótimo respeita a perda máxima do perfil (nunca o lance de -900)")
    var all_engine := true
    for i in 200:
        if Ladder.pick("mestre", fake, PackedStringArray(["e2e4","d2d4"]), rng).move != "e2e4": all_engine = false
    check(all_engine, "MESTRE: sem camada de erro (só o Stockfish limitado por Elo)")
    # ---------- progresso ----------
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.FILE))
    var pr = Progress.new()
    root.add_child(pr)
    pr.setup(null)
    check(pr.status("madeira") == "available" and pr.status("ferro") == "locked" and pr.status("challenger") == "locked", "conta nova: só MADEIRA liberado")
    check(pr.avatar_unlocked("warrior") and pr.avatar_unlocked("archer") and not pr.avatar_unlocked("mage") and not pr.avatar_unlocked("paladin"), "avatares iniciais livres; recompensas bloqueadas")
    check(pr.unlock_hint("mage") == "Derrote o BOT MADEIRA", "dica de desbloqueio do avatar")
    var got: Array = []
    pr.reward_unlocked.connect(func(b, r): got.append([b, r]))
    pr.report_victory("ferro", "w", PackedStringArray())
    check(not pr.is_defeated("ferro") and got.is_empty(), "vencer bot bloqueado não conta")
    pr.report_victory("madeira", "w", PackedStringArray())
    check(pr.status("madeira") == "defeated" and pr.status("ferro") == "available" and pr.status("bronze") == "locked", "vitória: MADEIRA derrotado, FERRO liberado, BRONZE bloqueado")
    check(got.size() == 1 and got[0][0] == "madeira" and got[0][1].get("id") == "mage" and pr.avatar_unlocked("mage"), "1ª vitória entrega a recompensa (avatar Mago)")
    pr.report_victory("madeira", "w", PackedStringArray())
    check(got.size() == 1, "repetir a vitória não gera outra recompensa")
    var pr2 = Progress.new()
    root.add_child(pr2)
    pr2.setup(null)
    check(pr2.is_defeated("madeira") and pr2.status("ferro") == "available", "progresso persiste (novo carregamento)")
    # ---------- fair play ----------
    var st := StubStage.new()
    root.add_child(st)
    for m in ["ranked", "casual", "online", "local"]:
        st.mode = m
        st.game.game_over = false
        check(FairPlay.engine_blocked(st, "analysis") and FairPlay.engine_blocked(st, "bot"), "engine BLOQUEADA em partida humana ativa (%s)" % m)
    st.mode = "bot"
    st.game.game_over = false
    check(not FairPlay.engine_blocked(st, "bot"), "bot pode consultar o Stockfish na partida contra o computador")
    st.mode = "ranked"
    st.game.game_over = true
    check(not FairPlay.engine_blocked(st, "analysis") and FairPlay.engine_blocked(st, "bot"), "depois da partida humana: análise liberada, bot nunca")
    var guarded = EngineScript.new("bot")
    guarded.guard = func() -> bool: return true
    root.add_child(guarded)
    var r: Dictionary = await guarded.search_move("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "go depth 1")
    var ev: Dictionary = await guarded.evaluate("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 4, 200)
    check(r.is_empty() and ev.is_empty() and not guarded.engine_ready, "com o guard ativo nenhuma consulta é feita (nem inicia o motor)")
    # ---------- Stockfish de verdade (opcional) ----------
    if OS.has_environment("FRAIHA_STOCKFISH"):
        var bot = EngineScript.new("bot")
        bot.allow_builtin = false
        root.add_child(bot)
        var ana = EngineScript.new("analysis")
        root.add_child(ana)
        await bot.start()
        await ana.start()
        check(bot.engine_kind() == "STOCKFISH" and ana.engine_kind() == "STOCKFISH", "BOT ENGINE = STOCKFISH e ANALYSIS ENGINE = STOCKFISH (instâncias separadas)")
        check(bot.instance_id != ana.instance_id and bot._proc.get("pid") != ana._proc.get("pid"), "processos diferentes para bot e análise")
        check(await bot.configure(Ladder.uci_options("madeira")), "perfil MADEIRA aplicado na instância do bot")
        var fen := "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
        var mv: Dictionary = await bot.search_move(fen, Ladder.go_command("madeira"))
        check(not String(mv.get("bestmove", "")).is_empty() and mv.lines.size() >= 3, "bot responde com MultiPV (%d linhas, %d ms)" % [mv.get("lines", {}).size(), int(mv.get("ms", 0))])
        var a: Dictionary = await ana.evaluate(fen, 12, 2000)
        check(int(a.get("depth", 0)) >= 12, "análise continua em força total depois do bot configurar Skill 0 (depth %d)" % int(a.get("depth", 0)))
        check(not ana.options_applied.has("Skill Level"), "a instância de análise nunca recebeu as opções do bot")
        # mate em 1 para o bot de força total
        await bot.configure(Ladder.uci_options("challenger"))
        var mate: Dictionary = await bot.search_move("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "go movetime 300")
        check(String(mate.get("bestmove", "")) == "a1a8", "CHALLENGER encontra o mate em 1 (a1a8)")
        bot.stop()
        ana.stop()
    else:
        print("SKIP Stockfish real (defina FRAIHA_STOCKFISH)")
    print("BOT_LADDER_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit(1 if failures else 0)
