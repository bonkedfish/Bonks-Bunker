// Disc plastic (D-117): base colour with a hot-stamp foil design on the flight plate and light scuffs. The top of the
// disc carries UVs 0..1 across its diameter; everything else has UV.x < 0 (plain plastic). design 0 = rings,
// 1 = star, 2 = bison. Used by scripts/discgolf/disc_mesh.gd.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.9, 0.3, 0.15);
uniform vec3 foil_color : source_color = vec3(0.85, 0.86, 0.9);
uniform float foil_metal = 0.9;
uniform float rough = 0.35;
uniform float coat = 0.4;
uniform int design = 0;
uniform float wear = 0.3;

float ring(float r, float a, float b) {
	return step(a, r) * step(r, b);
}

float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float ellipse(vec2 p, vec2 c, vec2 rad) {
	vec2 q = (p - c) / rad;
	return step(dot(q, q), 1.0);
}

float box(vec2 p, vec2 c, vec2 h) {
	vec2 q = abs(p - c);
	return step(q.x, h.x) * step(q.y, h.y);
}

float stamp(vec2 p) {
	float r = length(p);
	float m = ring(r, 0.47, 0.5);
	if (design == 0) {
		m = max(m, ring(r, 0.36, 0.38));
		float a = atan(p.y, p.x);
		float tick = step(0.82, fract(a / 6.2831853 * 16.0)) * ring(r, 0.39, 0.45);
		m = max(m, tick);
		m = max(m, step(r, 0.08));
	} else if (design == 1) {
		float d = sd_star5(vec2(p.x, -p.y), 0.36, 0.45);
		m = max(m, step(abs(d), 0.018));
		m = max(m, step(d, -0.06));
	} else {
		vec2 q = vec2(p.x, -p.y);
		float b = ellipse(q, vec2(0.04, -0.02), vec2(0.25, 0.14));
		b = max(b, ellipse(q, vec2(-0.08, 0.08), vec2(0.14, 0.13)));
		b = max(b, ellipse(q, vec2(-0.25, -0.03), vec2(0.08, 0.09)));
		b = max(b, box(q, vec2(-0.12, -0.2), vec2(0.025, 0.08)));
		b = max(b, box(q, vec2(0.18, -0.2), vec2(0.025, 0.08)));
		b = max(b, box(q, vec2(0.29, 0.02), vec2(0.04, 0.012)));
		float horn = ring(length(q - vec2(-0.24, 0.05)), 0.06, 0.08) * step(0.05, q.y);
		m = max(m, max(b, horn));
	}
	return m;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float scuffs(vec2 p) {
	float s = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float ang = hash(fi * 3.1) * 3.14159;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 c = vec2(hash(fi * 7.7), hash(fi * 1.3)) * 1.4 - 0.7;
		vec2 d = p - c;
		float along = dot(d, dir);
		float across = abs(dot(d, vec2(-dir.y, dir.x)));
		s = max(s, step(across, 0.006) * step(abs(along), 0.12 + 0.2 * hash(fi)));
	}
	return s;
}

void fragment() {
	vec3 col = base_color;
	float met = 0.0;
	float rgh = rough;
	if (UV.x >= 0.0) {
		vec2 p = (UV - 0.5) * 2.0;
		float m = stamp(p / 0.62);
		float s = scuffs(p) * wear;
		col = mix(col, foil_color, m * (1.0 - 0.6 * s));
		met = m * foil_metal;
		rgh = mix(rgh, 0.25, m);
		col = mix(col, vec3(0.92), s * 0.35 * (1.0 - m));
	}
	ALBEDO = col;
	METALLIC = met;
	ROUGHNESS = rgh;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.25;
}
