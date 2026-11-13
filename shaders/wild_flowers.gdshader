// WildFlowers — overgrown flower beds and weeds on generated landmarks (D-047). Each vertical quad (UV 0..1,
// v = 0 at the ground) is cut into a few leaning stems with a petal head each; everything else is discarded, so
// beds read as plants instead of coloured cards. COLOR = petal colour, UV2.x = per-quad seed. Lit as if facing
// up so both sides of a quad shade the same. No textures.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 stem_color : source_color = vec3(0.34, 0.33, 0.17);
uniform int stems = 6;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;  // v = 0 at the ground, 1 at the top
	float seed = UV2.x;
	float hit = 0.0;
	float petal = 0.0;
	for (int i = 0; i < stems; i++) {
		float fi = float(i) + seed;
		float x0 = 0.12 + 0.76 * hash(fi * 12.99);
		float lean = (hash(fi * 78.23) - 0.5) * 0.35;
		float h = 0.45 + 0.55 * hash(fi * 3.71);
		float x = x0 + lean * uv.y;
		float w = 0.022 * (1.0 - 0.6 * uv.y / h);
		if (uv.y < h && abs(uv.x - x) < w) {
			hit = 1.0;
		}
		vec2 d = vec2(uv.x - (x0 + lean * h), (uv.y - h) * 1.3);
		float r = 0.05 + 0.05 * hash(fi * 9.1);
		if (length(d) < r) {
			hit = 1.0;
			petal = 1.0;
		}
	}
	if (hit < 0.5) {
		discard;
	}
	ALBEDO = mix(stem_color, COLOR.rgb, petal);
	ROUGHNESS = 0.9;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
