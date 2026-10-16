extends RefCounted
## R124 · letras nítidas e com espaçamento certo em QUALQUER escala de tela. O jogo desenha em 1920x1080 e a
## tela reduz/aumenta (stretch canvas_items): com a fonte rasterizada, as letras ficavam com espaços tortos
## ("PERS ONALIZAÇÃO", "tes te"). Com MSDF (campo de distância) a letra escala sem perder forma nem espaço.
## As fontes de PIXEL do XEQUE (VT323, Jersey, Jacquard) ficam como estão (são pixeladas de propósito).
## Os arquivos .woff foram preparados para MSDF (tools/art/fontes_msdf_r124.py: glifos decompostos e o til
## do Cinzel no sentido certo).
const FONTS := [
	"res://account/fonts/Cinzel-Bold.woff", "res://account/fonts/Cinzel-SemiBold.woff",
	"res://ui_kit/fonts/Alegreya-Bold.woff", "res://ui_kit/fonts/Alegreya-Medium.woff",
	"res://marcha/art/fonts/oswald-latin-400-normal.woff", "res://marcha/art/fonts/oswald-latin-600-normal.woff",
	"res://marcha/art/fonts/oswald-latin-700-normal.woff", "res://xeque/art/fontes/Grenze-Bold.woff",
]
static var done := false

static func apply():
	if done: return
	done = true
	for p in FONTS:
		if not ResourceLoader.exists(p): continue
		var f = load(p)
		if f is FontFile:
			f.msdf_pixel_range = 16
			f.msdf_size = 64
			f.multichannel_signed_distance_field = true
