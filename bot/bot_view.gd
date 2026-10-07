extends RefCounted
## R51 · Fonte de dados dos cartões do Ranked (ranked/ranked_ui.gd) numa partida CONTRA O COMPUTADOR:
## mesmo formato do controlador do Ranked (human_color, status, clock, player(), in_match(), resign()).
## O layout da partida contra o bot é o do Ranked Madeira (pele ranked/board_skin.gd), igual para todos.
const Ladder = preload("res://bot/bot_ladder.gd")
const LeagueCatalog = preload("res://league/catalog.gd")
var stage
var ctrl

func _init(owner_stage, controller):
    stage = owner_stage
    ctrl = controller

var human_color: String:
    get: return ctrl.human_color
var status: String:
    get: return ctrl.status
var clock:
    get: return ctrl.clock
var mode_name: String:
    get: return "Contra o computador"

func in_match() -> bool:
    return ctrl.in_match()

func resign():
    if stage != null and stage.has_method("resign_bot"): stage.resign_bot()

func player(color: String) -> Dictionary:
    if color == ctrl.human_color:
        var acc = stage.get("account") if stage != null else null
        # a mesma liga/PL do cartão da Home: a maior entre os ritmos do Ranked (sem conta: Madeira 0)
        var lg := 0
        var pl := 0
        if acc != null and acc.get("ranked") is Dictionary:
            for m in acc.ranked:
                var st = acc.ranked[m]
                if not st is Dictionary: continue
                var l := clampi(int(st.get("league", 0)), 0, LeagueCatalog.IDS.size() - 1)
                var p := clampi(int(st.get("pl", 0)), 0, 100)
                if l > lg or (l == lg and p > pl):
                    lg = l
                    pl = p
        return {"league": lg, "pl": pl}
    var b: Dictionary = Ladder.bot(ctrl.bot_id) if not ctrl.bot_id.is_empty() else {}
    var lid := String(b.get("league", "madeira"))
    var idx := maxi(0, LeagueCatalog.IDS.find(lid))
    # retrato = o avatar da liga do bot (o mesmo que ele dá de recompensa na 1ª vitória)
    var rew := String(b.get("reward", {}).get("id", lid + "_reward")) if b.get("reward") is Dictionary else lid + "_reward"
    return {"nickname": String(b.get("name", "BOT")), "league": idx, "pl": 0, "connected": true,
        "sub": String(b.get("title", "Computador")).to_upper(), "avatar_id": rew}
