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
var promoted_now := false
var last_cue := ""
var slot := 0

func _ready():
    stage = get_parent()
    for id in ["wood","metal","capture","check","mate","win","loss","promotion","ui","bell"]:
        streams[id] = load("res://audio_v025/"+id+".wav")
    # R50 · sons padrão do xadrez (enviados pelo dono do projeto), iguais em todos os modos e temas
    var lance: AudioStream = load("res://audio_v025/padrao/movimento.mp3")
    streams["wood"] = lance
    streams["metal"] = lance
    streams["capture"] = load("res://audio_v025/padrao/captura.mp3")
    streams["promotion"] = load("res://audio_v025/padrao/promocao.mp3")
    streams["roque"] = load("res://audio_v025/padrao/roque.mp3")
    for i in range(4):
        var player = AudioStreamPlayer.new()
        player.volume_db = -14
        player.bus = "Effects"
        # R81 · Web: efeitos como SAMPLE (tocados pelo próprio navegador). Antes eram STREAM, pelo mixer do Godot,
        # que nesta build sem threads roda no mesmo laço do jogo: qualquer quadro pesado (Marcha/Xeque no celular)
        # deixava o som picotando. O mudo/volume do bus Effects é garantido aqui no código (_fx_ok / _fx_db).
        if OS.has_feature("web"): player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
        add_child(player)
        players.append(player)
    music = AudioStreamPlayer.new()
    music.name = "LeagueMusic"
    music.bus = "Music"
    # Long MP3s must not become full-length PCM WebAudio samples on iOS.
    if OS.has_feature("web"):
        music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
    add_child(music)
    web_music = OS.has_feature("web") and not OS.has_feature("editor")
    if web_music: _web_music_init()
    refresh_music()

## Efeitos ligados? (bus Effects e Master sem mudo, volume > 0)
func _fx_ok() -> bool:
    var b := AudioServer.get_bus_index("Effects")
    if AudioServer.is_bus_mute(0) or (b >= 0 and AudioServer.is_bus_mute(b)): return false
    return true

func play_cue(id: String, from_pos := 0.0):
    if not streams.has(id) or players.is_empty(): return
    if not _fx_ok(): return
    last_cue = id
    var player = players[slot]
    slot = (slot+1)%players.size()
    player.stream = streams[id]
    player.volume_db = -14
    player.pitch_scale = 1.0
    player.play(from_pos)

## R50 · momento do "toc" dentro de cada som novo (o movimento.mp3 tem ~0,5 s quase mudo antes do toc).
const HIT := {"wood": 0.50, "metal": 0.50, "capture": 0.07, "promotion": 0.07, "roque": 0.07}
## Toca o som do lance com o toc caindo quando a peça assenta na casa (fim da animação do tabuleiro).
## Sem animação (arrastar), o toc sai na hora. O arquivo não é alterado: só o ponto de início.
func play_move_cue(id: String):
    var game = stage.game
    var left := 0.0
    if not game.move_anim.is_empty() and game.move_anim_t < 1.0:
        left = (1.0 - game.move_anim_t) * game.move_anim_len
    var hit: float = HIT.get(id, 0.0)
    if left <= hit:
        play_cue(id, maxf(0.0, hit - left))
    else:
        get_tree().create_timer(left - hit).timeout.connect(play_cue.bind(id, 0.0))

func toggle_music():
    var index = AudioServer.get_bus_index("Music")
    AudioServer.set_bus_mute(index,not AudioServer.is_bus_mute(index))

## R34: modos à parte (XEQUE, MARCHA REAL) trocam a música de fundo enquanto estão abertos.
## "" = volta à música do tema (Home / partida de xadrez).
var music_override := ""
func set_music_override(path: String):
    if path != music_override: release_mode_samples()   # R99 · troca/saída de modo: solta as amostras do modo anterior
    music_override = path
    refresh_music()

## R99 · Web: cada AudioStream tocado como SAMPLE vira um AudioBuffer PCM no navegador (GodotAudio.samples) e o
## motor NÃO o remove quando o stream é liberado. Os efeitos do XEQUE/Marcha são recarregados a cada entrada (ID
## novo) → ~7 MB a mais por volta (Orca, R94). Aqui guardamos os IDs dos streams tocados pelos modos e, ao sair
## do modo, pedimos ao runtime (tools/web_release/audio_samples_release.py) para liberar essas amostras. O runtime
## só libera quando nenhuma reprodução ativa usa a amostra (as que ainda tocam saem quando terminam) e o motor
## registra de novo se o mesmo stream voltar a tocar. Os sons padrão (self.streams) ficam sempre registrados.
var _mode_sample_ids := {}
func _track_mode_stream(stream: AudioStream):
    if not OS.has_feature("web") or stream == null: return
    for s in streams.values():
        if s == stream: return
    _mode_sample_ids[stream.get_instance_id()] = true

func release_mode_samples() -> void:
    if _mode_sample_ids.is_empty(): return
    var ids := PackedStringArray()
    for id in _mode_sample_ids: ids.append("'%d'" % int(id))
    _mode_sample_ids.clear()
    if not OS.has_feature("web"): return
    JavaScriptBridge.eval("(() => { const G = window.fraihaGodotAudio; if (G && G.Sample.fraihaRelease) G.Sample.fraihaRelease([%s]); })()" % ",".join(ids))

## R34: efeito sonoro de um modo (mesmo bus "Effects": volume e MUTAR EFEITOS valem para ele).
func play_stream(stream: AudioStream, db := -8.0, pitch := 1.0, from_pos := 0.0):
    if stream == null or players.is_empty(): return
    if not _fx_ok(): return
    var player = players[slot]
    slot = (slot+1)%players.size()
    player.stream = stream
    player.volume_db = db
    player.pitch_scale = pitch
    player.play(from_pos)
    _track_mode_stream(stream)   # R99
    last_cue = String(stream.resource_path).get_file().get_basename()

func refresh_music():
    # Home and its internal pages always use Madeira, regardless of preview art.
    var theme: String = stage.game.visual_theme if stage.mode in ["local","bot","online","casual"] else "wood"
    var path: String = preload("res://cosmetics/theme_catalog.gd").get_theme(theme).music_path
    if not music_override.is_empty(): path = music_override
    if path == music_path: return
    if web_music:
        # R84 · Web: a música vai para o <audio> do navegador em PEDAÇOS (antes ia o arquivo inteiro em base64 numa
        # string só: no iPhone o MP3 de 4 MB do XEQUE existia 4–5 vezes ao mesmo tempo na memória, ~20–40 MB de pico
        # bem na entrada do modo) e fica guardada no navegador: voltar ao modo não transfere de novo.
        music.stop()
        music.stream = null
        music_path = path
        music_starts += 1
        _web_volume = -1.0
        var key := path.get_file()
        if bool(JavaScriptBridge.eval("window.fraihaMusic.use('%s') ? 1 : 0" % key)): return
        var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
        if bytes.is_empty():
            var tr = load(path) as AudioStreamMP3
            if tr == null: return
            bytes = tr.data
        JavaScriptBridge.eval("window.fraihaMusic.begin()")
        var CH := 262144
        var i := 0
        while i < bytes.size():
            JavaScriptBridge.eval("window.fraihaMusic.part('" + Marshalls.raw_to_base64(bytes.slice(i, mini(i + CH, bytes.size()))) + "')")
            i += CH
        bytes = PackedByteArray()
        JavaScriptBridge.eval("window.fraihaMusic.finish('%s')" % key)
        return
    var track = load(path) as AudioStreamMP3
    if track == null: return
    track.loop = true
    track.loop_offset = 0.0
    music.stop()
    music.stream = track
    music_path = path
    music_starts += 1
    music.play()

var web_music := false
var _web_volume := -1.0

func _web_music_init():
    JavaScriptBridge.eval("""
    (() => {
        if (window.fraihaMusic) return;
        const m = { el: new Audio(), url: null, vol: 0.65, hidden: false };
        m.el.loop = true; m.el.preload = 'auto';
        // Volume por GainNode (Web Audio): no iPhone o volume de <audio> é ignorado pelo navegador.
        m.graph = () => {
            if (m.gain) return;
            try {
                const C = window.AudioContext || window.webkitAudioContext;
                m.ctx = new C();
                m.gain = m.ctx.createGain();
                m.ctx.createMediaElementSource(m.el).connect(m.gain);
                m.gain.connect(m.ctx.destination);
                m.gain.gain.value = m.vol;
                m.el.volume = 1;
            } catch (e) { m.gain = null; }
        };
        m.tryPlay = () => {
            m.graph();
            if (m.ctx && m.ctx.state === 'suspended') m.ctx.resume().catch(() => {});
            if (m.url && m.vol > 0 && !m.hidden) m.el.play().catch(() => {});
        };
        // R84 · recebe o MP3 em pedaços e guarda até 3 músicas (Blob URL por nome); a mais antiga sai
        m.cache = {}; m.order = []; m.parts = [];
        m.begin = () => { m.parts = []; };
        m.part = (b64) => {
            const bin = atob(b64); const bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            m.parts.push(bytes);
        };
        m.play = (url) => { m.url = url; m.el.src = url; m.el.currentTime = 0; m.tryPlay(); };
        m.finish = (key) => {
            const url = URL.createObjectURL(new Blob(m.parts, { type: 'audio/mpeg' }));
            m.parts = [];
            m.cache[key] = url; m.order.push(key);
            while (m.order.length > 3) { const old = m.order.shift(); if (m.cache[old] && m.cache[old] !== url) URL.revokeObjectURL(m.cache[old]); delete m.cache[old]; }
            m.play(url);
        };
        m.use = (key) => { const url = m.cache[key]; if (!url) return false; m.order = m.order.filter(k => k !== key); m.order.push(key); m.play(url); return true; };
        m.setVolume = (v) => {
            m.vol = Math.max(0, Math.min(1, v));
            if (m.gain) m.gain.gain.value = m.vol; else m.el.volume = m.vol;
            if (m.vol <= 0) m.el.pause(); else if (m.el.paused) m.tryPlay();
        };
        // Navegadores só liberam áudio depois de um toque/tecla.
        for (const ev of ['pointerdown', 'touchend', 'keydown']) document.addEventListener(ev, () => { if (m.el.paused || (m.ctx && m.ctx.state !== 'running')) m.tryPlay(); }, true);
        document.addEventListener('visibilitychange', () => { m.hidden = document.hidden; if (m.hidden) m.el.pause(); else m.tryPlay(); });
        window.fraihaMusic = m;
    })()
    """)

func _web_music_volume():
    var bus = AudioServer.get_bus_index("Music")
    var master_mute = AudioServer.is_bus_mute(0)
    var v = 0.0 if (AudioServer.is_bus_mute(bus) or master_mute) else db_to_linear(AudioServer.get_bus_volume_db(bus) + AudioServer.get_bus_volume_db(0) + music.volume_db)
    if absf(v - _web_volume) > 0.001:
        _web_volume = v
        JavaScriptBridge.eval("window.fraihaMusic.setVolume(%f)" % v)

## R92 · nas partidas (xadrez, XEQUE, MARCHA) a música toca 20% mais baixa que na Home: dá para ouvir a voz do
## parceiro. O volume escolhido pelo jogador (controle/configuração) continua valendo por cima disso.
const MATCH_MUSIC_GAIN := 0.8
func _music_db_target() -> float:
    var in_match: bool = not music_override.is_empty() or stage.mode in ["local", "bot", "online", "casual"]
    return linear_to_db(MATCH_MUSIC_GAIN) if in_match else 0.0

func _process(_delta):
    var tdb := _music_db_target()
    if absf(music.volume_db - tdb) > 0.01: music.volume_db = tdb
    if web_music: _web_music_volume()
    var game = stage.game
    var theme: String = game.visual_theme
    refresh_music()
    if not game.game_started:
        previous_count = -1
        previous_end = false
        return
    var captures: int = game.captured_white.size()+game.captured_black.size()
    if previous_count >= 0 and game.move_count == previous_count+1:
        var moved_before: String = previous_board.get(game.last_from,"")
        var moved_after: String = game.pieces.get(game.last_to,"")
        # um som por lance: promoção > roque > captura > lance comum
        if moved_before.ends_with("P") and not moved_after.is_empty() and not moved_after.ends_with("P"):
            play_move_cue("promotion")
            promoted_now = true
        elif moved_before.ends_with("K") and absi(game.last_to.x - game.last_from.x) == 2:
            play_move_cue("roque")
        else:
            play_move_cue("capture" if captures > previous_captures else ("wood" if theme == "wood" else "metal"))
        # R50 · sem som de xeque e sem o sininho antigo de "sua vez" (tocava junto com o som novo do lance)
    if was_promotion and not game.promotion_pending and previous_count >= 0 and not promoted_now:
        play_cue("promotion")
    promoted_now = false
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
