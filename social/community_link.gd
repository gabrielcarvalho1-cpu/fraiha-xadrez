extends RefCounted
## R122 · COMUNIDADE: o convite permanente do servidor FRAIHA Xadrez no Discord (nunca expira; quem entra
## ganha o cargo Jogador). Um lugar só: se o convite mudar, troca-se aqui.
const URL := "https://discord.gg/27WRsrUGa6"
const TIP := "Comunidade FRAIHA no Discord"

static var opener: Callable   # testes: substitui OS.shell_open

static func open():
	if opener.is_valid(): opener.call(URL)
	else: OS.shell_open(URL)
