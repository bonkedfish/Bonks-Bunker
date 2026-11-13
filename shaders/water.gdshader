// Water — lakes, ponds and rivers of the generated map (D-047). Murky post-apocalyptic water: colour from shallow to
// deep by the depth stored in COLOR.r (x 8 m), small moving ripples from layered sine noise (no textures), a bit
// of fresnel brightening and a little transparency so shores blend. Mesh contract (WaterBuilder): UV = world (x, z).
shader_type spatial;
render_mode cull_disabled, depth_draw_always;

uniform vec3 shallow : source_color = vec3(0.32, 0.36, 0.28);
uniform vec3 deep : source_color = vec3(0.08, 0.13, 0.12);
uniform float depth_fade_m = 3.0;
uniform float wave_scale = 0.06;

float wave(vec2 p, float t) {
	return sin(p.x * 0.9 + t * 1.3) * 0.5 + sin(p.y * 1.1 - t * 1.1) * 0.5
		+ sin((p.x + p.y) * 2.3 + t * 2.1) * 0.25 + sin((p.x - p.y) * 3.1 - t * 1.7) * 0.15;
}

void fragment() {
	float depth = COLOR.r * 8.0;
	vec3 col = mix(shallow, deep, clamp(depth / depth_fade_m, 0.0, 1.0));
	vec2 p = UV;
	float t = TIME;
	float e = 0.15;
	float h = wave(p, t);
	vec3 n = normalize(vec3((wave(p + vec2(e, 0.0), t) - h) / e * wave_scale, 1.0, (wave(p + vec2(0.0, e), t) - h) / e * wave_scale));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col + fresnel * 0.15;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.75, 0.95, clamp(depth / depth_fade_m, 0.0, 1.0));
}
