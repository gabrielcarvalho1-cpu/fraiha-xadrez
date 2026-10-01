shader_type canvas_item;
// Fundo da tela de resultado: tabuleiro e HUD continuam visíveis, porém escurecidos e
// levemente desfocados. `amount` anima de 0 (nada) a 1 (efeito completo).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float blur : hint_range(0.0, 4.0) = 2.4;
uniform float darken : hint_range(0.0, 1.0) = 0.62;
uniform vec3 tint : source_color = vec3(0.0, 0.02, 0.01);

void fragment() {
    vec2 px = SCREEN_PIXEL_SIZE * (1.0 + 3.0 * amount);
    float lod = blur * amount;
    // 9 amostras em cruz/diagonal + LOD de mipmap: desfoque suave e barato (funciona na Web)
    vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.2;
    c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0) * 2.0, lod).rgb * 0.1;
    c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0) * 2.0, lod).rgb * 0.1;
    c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y) * 2.0, lod).rgb * 0.1;
    c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y) * 2.0, lod).rgb * 0.1;
    c += textureLod(screen_tex, SCREEN_UV + px * 1.5, lod).rgb * 0.1;
    c += textureLod(screen_tex, SCREEN_UV - px * 1.5, lod).rgb * 0.1;
    c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y) * 1.5, lod).rgb * 0.1;
    c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y) * 1.5, lod).rgb * 0.1;
    // vinheta: bordas mais escuras, centro (onde fica a arte) um pouco mais aberto
    float v = smoothstep(0.2, 0.95, distance(SCREEN_UV, vec2(0.5, 0.48)) * 1.3);
    float d = darken * amount * (0.85 + 0.35 * v);
    COLOR = vec4(mix(c, tint, clamp(d, 0.0, 0.9)), 1.0);
}
