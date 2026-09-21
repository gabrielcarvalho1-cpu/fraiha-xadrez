extends RefCounted
## Presentation catalog only. No competitive progression formula lives here.
const IDS = ["madeira","ferro","bronze","prata","ouro","platina","esmeralda","diamante","mestre","grande_mestre","challenger"]
const NAMES = ["Madeira","Ferro","Bronze","Prata","Ouro","Platina","Esmeralda","Diamante","Mestre","Grande Mestre","Challenger"]

static func index_of(id: String) -> int:
    return IDS.find(id)

static func theme_for(id: String) -> String:
    if id == "madeira": return "wood"
    if id == "ferro": return "iron"
    return id

static func entries(profile: Dictionary = {}) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var cosmetics = profile.get("unlocked_cosmetics", ["classic","wood"])
    var highest = maxi(0, index_of(String(profile.get("highest_league","madeira"))))
    for i in range(IDS.size()):
        var theme = theme_for(IDS[i])
        result.append({"league_id":IDS[i],"display_name":NAMES[i],"min_lp":0,"max_lp":100,
            "badge":IDS[i],"piece_theme":theme,"board_theme":theme,"environment_theme":theme,
            "unlocked":i <= highest or theme in cosmetics})
    return result

static func entry(id: String, profile: Dictionary = {}) -> Dictionary:
    var index = index_of(id)
    return entries(profile)[maxi(0,index)]
