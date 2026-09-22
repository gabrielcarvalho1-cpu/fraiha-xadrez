shader_type canvas_item;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
    vec4 pixel = texture(TEXTURE, UV);
    // Recolor the existing pixel-art plate without altering its silhouette.
    if (pixel.g > pixel.r * 1.12 && pixel.g > pixel.b * 1.05) {
        float light = clamp(pixel.g * 2.0 + 0.45, 0.0, 1.0);
        pixel.rgb = mix(vec3(0.60, 0.29, 0.025), vec3(1.0, 0.79, 0.20), light);
    }
    COLOR = pixel * tint;
}
