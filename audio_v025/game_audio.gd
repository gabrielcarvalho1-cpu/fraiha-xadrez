extends Node
## Presentation observer only; never sends moves or changes a game result.
var stage
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var music_path := ""
var music_starts := 0
var streams := {}
var previous_count := -1
var previous_captures := 0
var previous_board := {}
var previous_end := false
var previous_theme := ""
var was_promotion := false
var last_cue := ""
var slot := 0

func _ready():
    stage = get_parent()
    for id in ["wood","metal","capture","check","mate","win","loss","promotion","ui"]:
        streams[id] = load("res://audio_v025/"+id+".wav")
    for i in range(4):
        var player = AudioStreamPlayer.new()
        player.volume_db = -14
        player.bus = "Effects"
        add_child(player)
        players.append(player)
    music = AudioStreamPlayer.new()
    music.name = "LeagueMusic"
    music.bus = "Music"
    add_child(music)
    refresh_music()

func play_cue(id: String):
    if not streams.has(id) or players.is_empty(): return
    last_cue = id
    var player = players[slot]
    slot = (slot+1)%players.size()
    player.stream = streams[id]
    player.play()

func toggle_music():
    var index = AudioServer.get_bus_index("Music")
    AudioServer.set_bus_mute(index,not AudioServer.is_bus_mute(index))

func refresh_music():
    # Home and its internal pages always use Madeira, regardless of preview art.
    var theme: String = stage.game.visual_theme if stage.mode in ["local","bot","online"] else "wood"
    var path: String = preload("res://cosmetics/theme_catalog.gd").get_theme(theme).music_path
    if path == music_path: return
    var track = load(path) as AudioStreamMP3
    if track == null: return
    track.loop = true
    track.loop_offset = 0.0
    music.stop()
    music.stream = track
    music_path = path
    music.play()
    music_starts += 1

func _process(_delta):
    var game = stage.game
    var theme: String = game.visual_theme
    refresh_music()
    if not game.game_started:
        previous_count = -1
        previous_end = false
        return
    var captures: int = game.captured_white.size()+game.captured_black.size()
    if previous_count >= 0 and game.move_count == previous_count+1:
        play_cue("capture" if captures > previous_captures else ("wood" if theme == "wood" else "metal"))
        var moved_before: String = previous_board.get(game.last_from,"")
        var moved_after: String = game.pieces.get(game.last_to,"")
        if moved_before.ends_with("P") and not moved_after.is_empty() and not moved_after.ends_with("P"):
            play_cue("promotion")
        var checked = game.bot.rules.in_check(game.turn) if game.bot != null else game._in_check(game.turn)
        if checked and not game.game_over: play_cue("check")
    if was_promotion and not game.promotion_pending and previous_count >= 0:
        play_cue("promotion")
    if game.game_over and not previous_end and previous_count >= 0:
        var human: String = game.bot.human_color if game.bot != null else (game.online.color if game.online != null else "")
        if "MATE" in game.status:
            play_cue("mate")
            if not human.is_empty(): play_cue("loss" if game.turn == human else "win")
        elif "VENC" in game.status:
            var winning_color = "w" if "BRANCAS" in game.status else "b"
            play_cue("win" if human.is_empty() or winning_color == human else "loss")
    previous_count = game.move_count
    previous_captures = captures
    previous_board = game.pieces.duplicate()
    previous_end = game.game_over
    was_promotion = game.promotion_pending

func _exit_tree():
    for player in players:
        player.stop()
        player.stream = null
    if is_instance_valid(music):
        music.stop()
        music.stream = null
