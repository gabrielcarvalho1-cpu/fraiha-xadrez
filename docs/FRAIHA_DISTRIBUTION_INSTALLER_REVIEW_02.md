# Installer DEV: revisão estática v1.1

2026-10-06. P1 **PREPARADO / PENDENTE**, sem compiler encontrado no PATH, Program Files, Program Files (x86) ou AppData/Local/Programs nas buscas de nomes autorizadas. Diretórios inacessíveis foram reportados pelo rg; não afirmamos ausência global de ferramentas. Nenhum software instalado nem installer compilado, executado ou desinstalado.

Template revisado: `distribution/installer/FRAIHA-DEV.iss`. Instala somente o launcher registrado pelo Inno, exige versão/publisher/ICO explícitos, usa privilégios mínimos e identidade DEV, sem post-install run. Shortcuts atuais são `--dev-mock`; não instala payload real A e não constitui instalador completo do jogo V029/V030. Não mudar silenciosamente o shortcut para real sem feed/bootstrap aprovado.

Não há `[UninstallDelete]` recursivo, portanto o template não programa remoção de userdata externa/saves nem payload updater. Isso preserva payloads por desenho, mas **não prova** uninstall seguro: falta guard de reparse/junction em `InitializeUninstall`, verificação da raiz/ancestors/arquivos registrados e política de segunda instalação. Inno remover o launcher registrado por uma raiz substituída por junction ainda precisa ser analisado e testado. O AppId fixo também requer QA de segunda instalação e de seus registros de uninstall; não assumir independência só porque diretórios diferem. Os saves DEV ficam em userdata da instalação, portanto cleanup futuro precisa preservar esse diretório explicitamente.

Comando reproduzível quando compiler e ICO oficial aprovado existirem, sem inventar identidade de publisher ou caminho de asset:

```powershell
function Build-FraihaDevInstaller {
  param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [Parameter(Mandatory=$true)][string]$OfficialIcon,
    [Parameter(Mandatory=$true)][string]$Publisher
  )
  $compilerFile=(Resolve-Path -LiteralPath $Compiler -ErrorAction Stop).Path
  $iconFile=(Resolve-Path -LiteralPath $OfficialIcon -ErrorAction Stop).Path
  $release=Get-Content -LiteralPath './distribution/version.json' -Raw | ConvertFrom-Json
  & $compilerFile ("/DGameVersion="+$release.game_version) ("/DPublisher="+$Publisher) ("/DOfficialIcon="+$iconFile) './distribution/installer/FRAIHA-DEV.iss'
  if ($LASTEXITCODE) { throw 'Inno compilation failed' }
}
```

Os parâmetros obrigatórios são entradas humanas futuras, não valores obtidos nesta rodada. O caminho usual procurado foi `C:/Program Files (x86)/Inno Setup 6/ISCC.exe`; inexistente no checkpoint. Sem compiler/ICO/publisher aprovado não há comando executável completo honesto nem hash de installer para entregar.

QA obrigatória futura em sandbox/VM autorizada: instalação limpa/bootstrap A, upgrade B, uninstall com saves externos e outra instalação intactos; substituir raiz/subdiretórios/launcher por junction e recusar antes de remover qualquer arquivo; não usar recursive delete nem seguir links. Conferir shortcuts/registro/arquivos remanescentes, launcher/jogo abertos e instaladores simultâneos. Assinatura, publisher, identidade real e permissões permanecem gates de produção. Android/Steam/iOS/self-update não foram iniciados para compensar P1 ausente.
