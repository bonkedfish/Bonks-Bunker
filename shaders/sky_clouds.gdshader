// Sky with drifting clouds (D-099) and a day/night cycle (D-110): a gradient sky (horizon -> zenith) with a sun
// (or, after dark, moon) disc, and two layers of fbm
// clouds projected onto a flat cloud deck, drifting with `wind`. Weather (Atmosphere.set_weather) moves cloud_cover
// (0 clear .. 1 overcast), storm (darkens and greys everything) and flash (lightning lights the clouds). DayNight
// (Atmosphere.set_time_of_day) moves `night` (0 day .. 1 full night: the colours go deep blue and stars come out),
// `dusk` (orange along the horizon at sunrise and sunset) and `disc` (fades the sun/moon disc out at the horizon).
// Cheap:
// sky shaders render to a cached radiance map; only the visible sky pass runs the noise each frame.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.33, 0.48, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.86, 0.7, 0.5);
uniform vec3 ground_color : source_color = vec3(0.3, 0.25, 0.2);
uniform vec3 cloud_color : source_color = vec3(1.0, 0.95, 0.88);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.52, 0.5);
uniform vec3 storm_color : source_color = vec3(0.24, 0.25, 0.28);
uniform float curve = 0.35;
uniform float cloud_cover = 0.4;
uniform float storm = 0.0;
uniform float flash = 0.0;
uniform vec2 wind = vec2(0.004, 0.002);
uniform float cloud_scale = 1.6;
uniform float sun_size = 0.9994;
uniform vec3 night_top : source_color = vec3(0.015, 0.03, 0.08);
uniform vec3 night_horizon : source_color = vec3(0.06, 0.08, 0.16);
uniform vec3 night_cloud : source_color = vec3(0.16, 0.19, 0.28);
uniform vec3 night_cloud_shade : source_color = vec3(0.05, 0.06, 0.11);
uniform vec3 dusk_color : source_color = vec3(1.0, 0.55, 0.28);
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float disc = 1.0;
uniform float star_strength = 0.75;

float hash(vec2 p) {  // Hoskins hash12: no diagonal banding (the old fract(p * k) hash streaked)
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(1.7, 9.2);  // rotate each octave: no grid-aligned edges
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, -1.0, 1.0);
	float up = pow(clamp(h, 0.0, 1.0), curve);
	vec3 horizon = mix(horizon_color, night_horizon, night);
	vec3 top = mix(top_color, night_top, night);
	horizon = mix(horizon, dusk_color, dusk * 0.55 * (1.0 - night * 0.5));  // sunrise / sunset band
	vec3 col = mix(horizon, top, up);
	if (h < 0.0) {
		col = mix(horizon, mix(ground_color, night_top, night), clamp(-h * 4.0, 0.0, 1.0));
	}
	if (night > 0.02 && h > 0.0 && !AT_CUBEMAP_PASS) {  // stars: one bright point per cell of a coarse grid
		vec2 sp = dir.xz / max(h + 0.25, 0.1) * 26.0;
		vec2 si = floor(sp);
		float twinkle = 0.75 + 0.25 * sin(TIME * 1.7 + hash(si) * 40.0);
		float star = pow(hash(si + 7.1), 42.0) * step(0.55, hash(si * 1.7 + 3.3));
		float d = length(fract(sp) - 0.5 - (vec2(hash(si + 11.0), hash(si + 23.0)) - 0.5) * 0.6);
		col += vec3(0.85, 0.9, 1.0) * star * smoothstep(0.16, 0.0, d) * night * star_strength * twinkle
			* smoothstep(0.0, 0.25, h) * (1.0 - cloud_cover * 0.7);
	}
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = dot(dir, sun_dir);
	if (LIGHT0_ENABLED) {
		col += LIGHT0_COLOR * pow(max(sd, 0.0), 32.0) * 0.25 * (1.0 - storm) * disc;  // glow around the sun / moon
		vec3 body = mix(LIGHT0_COLOR * 4.0, vec3(0.86, 0.9, 1.0), night);  // the moon is a pale disc, not a bright one
		col = mix(col, body, smoothstep(sun_size, sun_size + 0.0003, sd) * (1.0 - cloud_cover * 0.8) * (1.0 - storm) * disc);
	}
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = dir.xz / max(h, 0.06) * cloud_scale * 0.35;  // a flat cloud deck seen from below
		vec2 t = wind * TIME;
		vec2 warp = vec2(fbm(uv * 0.6 + t), fbm(uv * 0.6 - t + 5.3)) - 0.5;  // bends the noise grid so no straight edges show
		float n = fbm(uv + warp * 0.9 + t) * 0.65 + fbm(uv * 2.7 + warp - t * 1.6) * 0.35;
		float edge = mix(0.62, 0.25, clamp(cloud_cover + storm * 0.4, 0.0, 1.0));
		float c = smoothstep(edge, edge + 0.22, n) * smoothstep(0.0, 0.12, h);
		vec3 cc = mix(mix(cloud_color, night_cloud, night), mix(cloud_shade, night_cloud_shade, night),
			smoothstep(edge, edge + 0.5, n));
		cc = mix(cc, dusk_color * 0.9, dusk * 0.45 * (1.0 - night * 0.6));
		cc = mix(cc, storm_color, storm);
		cc += vec3(0.9, 0.9, 1.0) * flash * c;
		col = mix(col, cc, c);
	}
	col = mix(col, storm_color * (0.8 + 0.4 * up), storm * 0.75);
	col += vec3(0.6, 0.62, 0.7) * flash * 0.35;
	COLOR = col;
}
