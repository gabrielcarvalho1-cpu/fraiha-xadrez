extends RefCounted
## Endereço do servidor multiplayer, em UM lugar só (conta, Casual, Ranked, Amigos usam o mesmo).
## Ordem (a última que existir vence):
##   1. online.cfg [online] server_url ............ servidor oficial (produção)
##   2. online.cfg [staging] server_url ........... só em builds com a feature "staging"
##                                                   (preset "Web Alpha" do export_presets.cfg)
##   3. online.local.cfg (fora do Git) ............. só no editor (F5)
##   4. online.cfg ao lado do executável ........... só desktop exportado
##   5. variável de ambiente FRAIHA_SERVER_URL ..... testes/depuração
## Não há segredo aqui: são só URLs públicas wss://.
static func server_url() -> String:
    var url := ""
    var config = ConfigFile.new()
    if config.load("res://online.cfg") == OK:
        url = String(config.get_value("online", "server_url", ""))
        if OS.has_feature("staging"):
            url = String(config.get_value("staging", "server_url", url))
    if OS.has_feature("editor"):
        var dev = ConfigFile.new()
        if dev.load("res://online.local.cfg") == OK:
            url = String(dev.get_value("online", "server_url", url))
    if not OS.has_feature("web") and not OS.has_feature("editor"):
        var side = ConfigFile.new()
        if side.load(OS.get_executable_path().get_base_dir() + "/online.cfg") == OK:
            url = String(side.get_value("online", "server_url", url))
    if OS.has_environment("FRAIHA_SERVER_URL"): url = OS.get_environment("FRAIHA_SERVER_URL")
    return url

static func channel() -> String:
    return "staging" if OS.has_feature("staging") else "produção"
