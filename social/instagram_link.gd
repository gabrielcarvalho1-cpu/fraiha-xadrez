extends RefCounted
## R176 · INSTAGRAM oficial do FRAIHA Xadrez (ao lado da COMUNIDADE/Discord). Abre direto o perfil.
const URL := "https://www.instagram.com/fraihaxadrez/"
const HANDLE := "@fraihaxadrez"
const TIP := "Instagram do FRAIHA Xadrez (@fraihaxadrez)"

static var opener: Callable   # testes: substitui OS.shell_open

static func open():
	if opener.is_valid(): opener.call(URL)
	else: OS.shell_open(URL)
