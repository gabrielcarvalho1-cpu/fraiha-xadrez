shader_type canvas_item;
// R139 · cores do tabuleiro sobre a arte da Madeira (visual_v018/casas_madeira.png, 8x8 casas).
// Cada pixel guarda a luz/sombra da arte e ganha a cor escolhida (mapa de gradiente) — a textura não muda.
// Mesma conta de tools/art/cores_madeira_r139.py (prévia aprovada).
uniform vec4 light_color : source_color = vec4(0.94, 0.85, 0.71, 1.0);
uniform vec4 dark_color : source_color = vec4(0.71, 0.53, 0.39, 1.0);
uniform vec3 stats_light = vec3(0.6315, 0.6688, 0.6904);
uniform vec3 stats_dark = vec3(0.332, 0.3672, 0.4393);

vec3 grad(float t, vec3 c) {
	vec3 lo = c * 0.86;
	vec3 hi = clamp(c * 1.06 + 0.02, 0.0, 1.0);
	return t < 0.5 ? mix(lo, c, t * 2.0) : mix(c, hi, t * 2.0 - 1.0);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float l = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	ivec2 cell = ivec2(floor(clamp(UV, 0.0, 0.9999) * 8.0));
	bool light = (cell.x + cell.y) % 2 == 0;
	vec3 st = light ? stats_light : stats_dark;
	vec3 c = light ? light_color.rgb : dark_color.rgb;
	float t = clamp((l - st.x) / (st.z - st.x + 1e-6), 0.0, 1.0);
	float med = (st.y - st.x) / (st.z - st.x + 1e-6);
	t = t < med ? t / med * 0.5 : 0.5 + (t - med) / (1.0 - med) * 0.5;
	COLOR = vec4(grad(t, c), src.a) * vec4(1.0);
}
