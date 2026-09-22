extends RefCounted
## Local profile foundation. Gameplay never awards LP, wins or cosmetics here.
const Catalog = preload("res://league/catalog.gd")
const SCHEMA_VERSION = 1
const SAVE_PATH = "user://league_profile_v024.json"
var data: Dictionary = defaults()
var unsupported_schema := false

static func defaults() -> Dictionary:
    return {"schema_version":SCHEMA_VERSION,"current_league":"madeira","lp":0,"wins":0,"losses":0,
        "games_played":0,"highest_league":"madeira","unlocked_cosmetics":["classic","wood"]}

static func _count(value, maximum: int) -> int:
    if not (value is int or value is float): return 0
    if not is_finite(float(value)): return 0
    return clampi(int(value),0,maximum)

static func validated(value: Dictionary) -> Dictionary:
    var clean = defaults()
    var current = value.get("current_league","madeira")
    if current is String and Catalog.IDS.has(current): clean.current_league = current
    var highest = value.get("highest_league",clean.current_league)
    if highest is String and Catalog.IDS.has(highest): clean.highest_league = highest
    if Catalog.index_of(clean.highest_league) < Catalog.index_of(clean.current_league):
        clean.highest_league = clean.current_league
    clean.lp = _count(value.get("lp",0),100)
    clean.wins = _count(value.get("wins",0),1000000)
    clean.losses = _count(value.get("losses",0),1000000)
    clean.games_played = maxi(clean.wins+clean.losses,_count(value.get("games_played",0),2000000))
    var cosmetics = value.get("unlocked_cosmetics",[])
    if cosmetics is Array:
        for cosmetic in cosmetics:
            if not cosmetic is String: continue
            var allowed = cosmetic in ["classic","wood","iron","bronze","silver","gold"] or Catalog.IDS.has(cosmetic)
            if allowed and not cosmetic in clean.unlocked_cosmetics:
                clean.unlocked_cosmetics.append(cosmetic)
    return clean

func load_profile(path: String = SAVE_PATH) -> Error:
    data = defaults()
    unsupported_schema = false
    if not FileAccess.file_exists(path): return save_profile(path)
    var file = FileAccess.open(path,FileAccess.READ)
    if file == null: return FileAccess.get_open_error()
    if file.get_length() > 65536: return ERR_FILE_CORRUPT
    var parsed = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary: return ERR_PARSE_ERROR
    if parsed.get("schema_version",SCHEMA_VERSION) != SCHEMA_VERSION:
        unsupported_schema = true
        return ERR_FILE_UNRECOGNIZED
    data = validated(parsed)
    return OK

func save_profile(path: String = SAVE_PATH) -> Error:
    if unsupported_schema: return ERR_FILE_UNRECOGNIZED
    data = validated(data)
    var temp = path + ".tmp"
    var file = FileAccess.open(temp,FileAccess.WRITE)
    if file == null: return FileAccess.get_open_error()
    file.store_string(JSON.stringify(data,"\t"))
    file.flush()
    file.close()
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))

func snapshot() -> Dictionary:
    return data.duplicate(true)
