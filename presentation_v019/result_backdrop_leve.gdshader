shader_type canvas_item;
// R92 · versão leve do fundo da tela de resultado para a Web no celular: só escurece (com vinheta), SEM ler a tela.
// A versão com desfoque (result_backdrop.gdshader) copia a tela inteira e gera mipmaps a cada quadro — caro demais
// para a GPU do iPhone no fim de partidas longas. Mesmos parâmetros (`amount` anima de 0 a 1).
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float darken : hint_range(0.0, 1.0) = 0.62;
uniform vec3 tint : source_color = vec3(0.0, 0.02, 0.01);

void fragment() {
    float v = smoothstep(0.2, 0.95, distance(SCREEN_UV, vec2(0.5, 0.48)) * 1.3);
    float d = (darken + 0.12) * amount * (0.85 + 0.35 * v);
    COLOR = vec4(tint, clamp(d, 0.0, 0.92));
}
