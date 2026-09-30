shader_type canvas_item;
render_mode blend_add;
// Brilho do próprio botão da arte: soma luz proporcional ao que já é claro/dourado
// (bordas, texto e ícone reluzem; o fundo escuro quase não muda). Sem caixa por cima.
uniform float strength = 0.7;
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    float gold = smoothstep(0.30, 0.85, lum) * clamp((c.r - c.b) * 2.5 + 0.35, 0.0, 1.0);
    float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
    vec3 add = c.rgb * (0.10 + gold * strength) * pulse;
    // Borda externa levemente mais quente.
    add += vec3(0.10, 0.07, 0.02) * gold * pulse;
    COLOR = vec4(add, c.a);
}
