extends RefCounted
## Endereço do servidor multiplayer, em UM lugar só (conta, Casual, Ranked, Amigos, XEQUE e Marcha online
## usam o mesmo). Não há segredo aqui: são só URLs públicas wss://.
##
## AMBIENTE da build (feature de export, ver export_presets.cfg):
##   - "staging"    → preset "Web Alpha" (QA/testes): usa online.cfg [staging] server_url.
##   - "production" → presets oficiais ("Web Producao", "Windows Desktop"): usa online.cfg [online] server_url.
##   - nenhuma      → editor / testes / builds locais: SEM servidor por padrão (R181).
## Ordem (a última que existir vence):
##   1. online.cfg [online] server_url ............ só em builds com a feature "production"
##   2. online.cfg [staging] server_url ........... só em builds com a feature "staging"
##   3. online.local.cfg (fora do Git) ............. só no editor (F5)
##   4. online.cfg ao lado do executável ........... só desktop exportado
##   5. variável de ambiente FRAIHA_SERVER_URL ..... testes/depuração
## Fail-closed: build marcada como produção que acabe apontando para o servidor de staging (ou marcada como
## staging E produção ao mesmo tempo) fica SEM servidor ("") em vez de jogar online no ambiente errado.
## R181 · TRAVA INVERSA (incidente de 24/10: um teste local entrou na fila Casual de PRODUÇÃO): build SEM a feature
## "production" nunca usa o servidor de produção, nem por variável/arquivo, a não ser com FRAIHA_ALLOW_PRODUCTION=1
## (ação consciente). Sem configuração = sem online.
static func server_url() -> String:
    var url := ""
    var prod_url := ""
    var config = ConfigFile.new()
    if config.load("res://online.cfg") == OK:
        prod_url = String(config.get_value("online", "server_url", ""))
        if OS.has_feature("production"): url = prod_url
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
    else:
        url = non_production_guard(url, prod_url, OS.get_environment("FRAIHA_ALLOW_PRODUCTION") == "1")
    return url

## R181 · build que NÃO é a oficial de produção: o servidor de produção fica bloqueado (vira "" = sem online).
static func non_production_guard(url: String, prod_url: String, allow: bool) -> String:
    if allow or url.is_empty(): return url
    var u := url.to_lower().trim_suffix("/")
    var p := prod_url.to_lower().trim_suffix("/")
    if (not p.is_empty() and u == p) or u.contains("fraiha-xadrez.onrender.com"):
        push_warning("FRAIHA: build de teste/local apontando para o servidor de PRODUÇÃO (%s): bloqueado, online desligado." % url)
        return ""
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
