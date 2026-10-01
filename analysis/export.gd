extends RefCounted
## Exportação dos lances de uma partida (texto / PGN / print) para o jogador guardar e
## analisar onde quiser. Nada aqui depende de motor nem de servidor.
##   • text_of(record, sans): bloco de notas em português (lances como aparecem no jogo) + PGN
##     padrão (letras inglesas: N B R Q K) para importar no Lichess/Chess.com.
##   • copy(text): área de transferência (PC e Web).
##   • save_text(text, name) / save_png(image, name): PC → pasta Downloads (ou Documentos);
##     Web → download pelo navegador. Retorna mensagem para o jogador.

const PT_TO_EN := {"C": "N", "B": "B", "T": "R", "D": "Q", "R": "K"}

static func pgn_san(san: String) -> String:
    if san.is_empty(): return san
    var out := san
    var first := out.substr(0, 1)
    if first in PT_TO_EN and out.length() > 1 and (out.substr(1, 1).to_lower() == out.substr(1, 1) or out.substr(1, 1) == "x"):
        out = PT_TO_EN[first] + out.substr(1)
    var eq := out.find("=")
    if eq >= 0 and eq + 1 < out.length():
        var p := out.substr(eq + 1, 1)
        if p in PT_TO_EN: out = out.substr(0, eq + 1) + PT_TO_EN[p] + out.substr(eq + 2)
    return out

static func result_tag(record) -> String:
    var human := String(record.human_color)
    match String(record.result):
        "win": return "1-0" if human != "b" else "0-1"
        "loss": return "0-1" if human != "b" else "1-0"
        "draw": return "1/2-1/2"
    return "*"

static func date_text(record) -> String:
    var ts: int = int(record.finished_at) if int(record.finished_at) > 0 else int(record.started_at)
    if ts <= 0: ts = int(Time.get_unix_time_from_system())
    var d := Time.get_datetime_dict_from_unix_time(ts)
    return "%02d/%02d/%04d" % [d.day, d.month, d.year]

static func pgn_date(record) -> String:
    var ts: int = int(record.finished_at) if int(record.finished_at) > 0 else int(record.started_at)
    if ts <= 0: ts = int(Time.get_unix_time_from_system())
    var d := Time.get_datetime_dict_from_unix_time(ts)
    return "%04d.%02d.%02d" % [d.year, d.month, d.day]

## Linha de lances numerada: "1. e4 e5 2. Cf3 Cc6 …"
static func move_line(sans: Array, english := false, start_ply := 0) -> String:
    var parts := []
    for i in sans.size():
        var ply := start_ply + i
        var san := pgn_san(String(sans[i])) if english else String(sans[i])
        if ply % 2 == 0: parts.append("%d. %s" % [ply / 2 + 1, san])
        elif i == 0: parts.append("%d... %s" % [ply / 2 + 1, san])
        else: parts.append(san)
    return " ".join(parts)

static func names(record) -> Array:
    var human := String(record.human_color)
    var me := String(record.player_name) if not String(record.player_name).is_empty() else "Jogador"
    var opp := String(record.opponent_name) if not String(record.opponent_name).is_empty() else "Adversário"
    if human == "b": return [opp, me]
    return [me, opp]

static func text_of(record, sans: Array) -> String:
    var n := names(record)
    var mode_names := {"bot": "Contra o computador", "casual": "Online casual", "ranked": "Ranqueada", "local": "Local", "friend": "Amigo"}
    var res_names := {"win": "Vitória", "loss": "Derrota", "draw": "Empate"}
    var lines := []
    lines.append("FRAIHA XADREZ — PARTIDA DE %s" % date_text(record))
    lines.append("Brancas: %s   Pretas: %s" % [n[0], n[1]])
    var res := String(res_names.get(String(record.result), ""))
    var reason := String(record.result_reason)
    lines.append("Modo: %s   Resultado: %s%s" % [mode_names.get(String(record.mode), String(record.mode)), res if res != "" else "—", (" (" + reason + ")") if reason != "" else ""])
    if not String(record.start_fen).is_empty(): lines.append("Posição inicial (FEN): " + String(record.start_fen))
    lines.append("")
    lines.append("LANCES (%d):" % sans.size())
    lines.append(move_line(sans))
    lines.append("")
    lines.append("PGN (para importar em outro programa):")
    lines.append("[Event \"FRAIHA Xadrez\"]")
    lines.append("[Date \"%s\"]" % pgn_date(record))
    lines.append("[White \"%s\"]" % n[0])
    lines.append("[Black \"%s\"]" % n[1])
    lines.append("[Result \"%s\"]" % result_tag(record))
    if not String(record.start_fen).is_empty():
        lines.append("[SetUp \"1\"]")
        lines.append("[FEN \"%s\"]" % String(record.start_fen))
    lines.append("")
    lines.append(move_line(sans, true) + " " + result_tag(record))
    return "\n".join(lines) + "\n"

static func file_stem(record) -> String:
    var ts: int = int(record.finished_at) if int(record.finished_at) > 0 else int(Time.get_unix_time_from_system())
    var d := Time.get_datetime_dict_from_unix_time(ts)
    return "fraiha_partida_%04d-%02d-%02d_%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute]

static func copy(text: String) -> String:
    DisplayServer.clipboard_set(text)
    return "Lances copiados. Cole num bloco de notas (Ctrl+V)."

static func _save_dir() -> String:
    for which in [OS.SYSTEM_DIR_DOWNLOADS, OS.SYSTEM_DIR_DOCUMENTS, OS.SYSTEM_DIR_PICTURES]:
        var d := OS.get_system_dir(which)
        if not d.is_empty() and DirAccess.dir_exists_absolute(d): return d
    return ProjectSettings.globalize_path("user://")

static func _save_bytes(bytes: PackedByteArray, file_name: String, mime: String) -> String:
    if OS.has_feature("web"):
        JavaScriptBridge.download_buffer(bytes, file_name, mime)
        return "Download iniciado: " + file_name
    var dir := _save_dir()
    var path := dir.path_join(file_name)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null: return "Não foi possível salvar em " + dir
    f.store_buffer(bytes)
    f.close()
    OS.shell_show_in_file_manager(path, true)
    return "Salvo em " + path

static func save_text(text: String, stem: String) -> String:
    return _save_bytes(text.to_utf8_buffer(), stem + ".txt", "text/plain")

static func save_png(image: Image, stem: String) -> String:
    if image == null: return "Não foi possível capturar a tela."
    return _save_bytes(image.save_png_to_buffer(), stem + ".png", "image/png")
