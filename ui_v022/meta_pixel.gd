extends RefCounted
## Meta Pixel (só Web). Repassa eventos para window.fraihaTrack / fraihaTrackOnce, que vêm do
## web/meta_pixel/fraiha-pixel.js (embutido no html/head_include dos presets Web).
## Se a pessoa recusou os cookies, o pixel vira no-op lá no JS: daqui nunca sai nada a mais.
## NUNCA mandar dado pessoal (e-mail, nickname, id de conta) como parâmetro.

static func track(event_name: String, custom := false) -> void:
    if not OS.has_feature("web"): return
    var kind := "trackCustom" if custom else "track"
    JavaScriptBridge.eval("try{if(window.fraihaTrack)window.fraihaTrack(" + JSON.stringify(kind) + "," + JSON.stringify(event_name) + ")}catch(e){}", true)

## Dispara uma vez só por aparelho/navegador (ex.: primeira partida).
static func track_once(event_name: String, custom := true) -> void:
    if not OS.has_feature("web"): return
    var kind := "trackCustom" if custom else "track"
    JavaScriptBridge.eval("try{if(window.fraihaTrackOnce)window.fraihaTrackOnce(" + JSON.stringify(kind) + "," + JSON.stringify(event_name) + "," + JSON.stringify(event_name) + ")}catch(e){}", true)
