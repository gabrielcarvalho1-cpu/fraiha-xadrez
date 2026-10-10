extends RefCounted
## Endereço do servidor multiplayer, em UM lugar só (conta, Casual, Ranked, Amigos, XEQUE e Marcha online
## usam o mesmo). Não há segredo aqui: são só URLs públicas wss://.
##
## AMBIENTE da build (feature de export, ver export_presets.cfg):
##   - "staging"    → preset "Web Alpha" (QA/testes): usa online.cfg [staging] server_url.
##   - "production" → preset "Web Producao": usa online.cfg [online] server_url e NUNCA a seção [staging].
##   - nenhuma      → editor/desktop/testes: [online], com os ajustes de depuração abaixo.
## Ordem (a última que existir vence):
##   1. online.cfg [online] server_url ............ servidor oficial (produção)
##   2. online.cfg [staging] server_url ........... só em builds com a feature "staging"
##   3. online.local.cfg (fora do Git) ............. só no editor (F5)
##   4. online.cfg ao lado do executável ........... só desktop exportado
##   5. variável de ambiente FRAIHA_SERVER_URL ..... testes/depuração
## Fail-closed: build marcada como produção que acabe apontando para o servidor de staging (ou marcada como
## staging E produção ao mesmo tempo) fica SEM servidor ("") em vez de jogar online no ambiente errado.
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
    if OS.has_feature("production"):
        var staging_url := ""
        if config.load("res://online.cfg") == OK:
            staging_url = String(config.get_value("staging", "server_url", ""))
        url = production_guard(url, staging_url, OS.has_feature("staging"))
    return url

## Trava da build de PRODUÇÃO (separada para ser testada): servidor de staging, ausente ou build marcada
## também como staging → "" (sem online), nunca o servidor errado.
static func production_guard(url: String, staging_url: String, also_staging: bool) -> String:
    if also_staging or url.is_empty() or "staging" in url.to_lower() or (not staging_url.is_empty() and url == staging_url):
        push_error("FRAIHA: build de PRODUÇÃO com servidor de staging/ausente (%s); online desligado." % url)
        return ""
    return url

## "staging" (QA), "produção" (build de produção) ou "dev" (editor/desktop/testes sem feature de ambiente).
static func channel() -> String:
    if OS.has_feature("staging"): return "staging"
    if OS.has_feature("production"): return "produção"
    return "dev"
