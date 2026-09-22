extends RefCounted
## Local foundation only; never connected to casual/bot results.
const Catalog = preload("res://league/catalog.gd")
const MODES = {"blitz":{"name":"Relâmpago","minutes":3},"rapid":{"name":"Rápida","minutes":5},"normal":{"name":"Normal","minutes":10},"classical":{"name":"Convencional","minutes":20}}
const SAVE = "user://ranked_foundation.cfg"
var ratings: Dictionary = {}

func _init():
    for mode in MODES:
        ratings[mode] = {"league":0,"lp":0,"wins":0,"losses":0,"draws":0,"games":0,"highest_league":0}

func load_local(path: String = SAVE):
    var config = ConfigFile.new()
    if config.load(path) != OK: return
    for mode in MODES:
        for key in ratings[mode]:
            ratings[mode][key] = maxi(0,int(config.get_value(mode,key,0)))
        ratings[mode].league = mini(ratings[mode].league,Catalog.IDS.size()-1)
        ratings[mode].lp = mini(ratings[mode].lp,100)
        ratings[mode].highest_league = clampi(ratings[mode].highest_league,ratings[mode].league,Catalog.IDS.size()-1)

func save_local(path: String = SAVE) -> Error:
    var config = ConfigFile.new()
    for mode in MODES:
        for key in ratings[mode]: config.set_value(mode,key,ratings[mode][key])
    return config.save(path)

static func points(opponent_difference: int, result: String) -> int:
    # Unspecified draws are neutral; differences beyond 100 use the outer band.
    if result == "draw": return 0
    if result not in ["win","loss"]: return 0
    var band = [6,-6]
    if opponent_difference >= 60: band = [10,-3]
    elif opponent_difference >= 30: band = [8,-4]
    elif opponent_difference <= -60: band = [3,-10]
    elif opponent_difference <= -30: band = [4,-8]
    return band[0] if result == "win" else band[1]

func apply_result(mode: String, result: String, opponent_difference: int) -> bool:
    if not MODES.has(mode) or result not in ["win","loss","draw"]: return false
    var data: Dictionary = ratings[mode]
    data.games += 1
    data[{"win":"wins","loss":"losses","draw":"draws"}[result]] += 1
    data.lp = maxi(0,data.lp + points(opponent_difference,result))
    while data.lp >= 100 and data.league < Catalog.IDS.size()-1:
        data.lp -= 100
        data.league += 1
    data.lp = mini(data.lp,100)
    data.highest_league = maxi(data.highest_league,data.league)
    return true

func summary(mode: String) -> String:
    var data: Dictionary = ratings[mode]
    return "%s · %d min — %s · %d / 100 PL\n%d vitórias · %d derrotas · %d empates · %d partidas\nMaior liga: %s" % [MODES[mode].name,MODES[mode].minutes,Catalog.NAMES[data.league],data.lp,data.wins,data.losses,data.draws,data.games,Catalog.NAMES[data.highest_league]]
