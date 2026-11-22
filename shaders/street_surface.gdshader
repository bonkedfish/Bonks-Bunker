// StreetSurface — roads, alleys, driveways, sidewalks and curbs of the generated map (D-043). Photo texture
// (albedo/normal/ARM) tiled in world metres so overlapping strips at intersections match, optional slab joints
// (concrete) and painted lane lines that wear away and stop at intersections.
// Mesh contract (written by tools/map_import/build_cells.gd):
//   UV   = world (x, z) in metres
//   UV2  = (metres across from the strip's centre line, metres along the strip)
//   COLOR.r = centre line: 0 none, 0.5 dashed yellow, 1 double solid yellow
//   COLOR.g = lanes per direction / 4 (white dashed lines between them)
//   COLOR.b = strip half width / 16 m,  COLOR.a = 1 paint lines here, 0 not (intersection)
// Abandonment (D-115), all off at 0 so each surface opts in through its material: a second texture blended in
// patches (alt_*, breaks up repeats), dirt/gravel drifted along the strip edges and in scattered patches
// (edge_*), a crack network with weeds growing in it, potholes and darker repaired patches. All procedural in
// world/strip space, so existing cells pick it up without a re-bake.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 4.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float joint_spacing_m = 0.0;  // 0 = no slab joints
uniform bool centre_joint = false;    // concrete roads: a joint along the centre line too
uniform float line_wear = 0.35;       // 0 = fresh paint, 1 = gone
uniform vec3 yellow : source_color = vec3(0.78, 0.62, 0.18);
uniform vec3 white : source_color = vec3(0.82, 0.82, 0.78);

uniform sampler2D alt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alt_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D edge_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D edge_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D edge_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float alt_tile_m = 5.0;
uniform float alt_mix = 0.0;         // share of the surface in the second texture
uniform float edge_tile_m = 2.5;
uniform float edge_dirt_m = 0.0;     // width of the dirt drifted in from each edge
uniform float drift_amount = 0.0;    // share covered by scattered dirt patches
uniform float crack_amount = 0.0;    // share of the surface with cracks
uniform float weed_amount = 0.0;     // share of cracks / joints with weeds in them
uniform float pothole_amount = 0.0;  // chance per 7 m cell of a pothole
uniform float patch_amount = 0.0;    // chance per 3 x 6 m block of a repaired patch
uniform vec3 weed_color : source_color = vec3(0.30, 0.34, 0.13);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.58 + vnoise(p * 2.13 + 7.1) * 0.27 + vnoise(p * 4.71 + 3.3) * 0.15;
}

// Distance to the nearest crack: the edges between Voronoi cells (f2 - f1), warped so they wander.
float crack_dist(vec2 p) {
	p += vec2(vnoise(p * 1.7), vnoise(p * 1.7 + 9.2)) * 0.6;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
			float d = length(g + o - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

float band(float x, float centre, float half_w) {
	return 1.0 - smoothstep(half_w * 0.7, half_w, abs(x - centre));
}

void fragment() {
	vec2 uv = UV / tile_m;
	vec3 alb = texture(albedo_tex, uv).rgb * tint;
	vec3 arm = texture(arm_tex, uv).rgb;
	vec3 nrm = texture(normal_tex, uv).rgb;
	float rough = arm.g;
	float across = UV2.x;
	float along = UV2.y;

	if (joint_spacing_m > 0.0) {
		float j = band(fract(along / joint_spacing_m) * joint_spacing_m, 0.0, 0.012)
			+ band(fract(along / joint_spacing_m) * joint_spacing_m, joint_spacing_m, 0.012);
		if (centre_joint) {
			j = max(j, band(across, 0.0, 0.012));
		}
		alb *= 1.0 - 0.55 * clamp(j, 0.0, 1.0);
		if (weed_amount > 0.0) {  // weeds in the slab joints
			float wj = clamp(j, 0.0, 1.0) * step(1.0 - weed_amount, vnoise(UV * 0.9));
			alb = mix(alb, weed_color * (0.7 + 0.6 * vnoise(UV * 9.0)), wj);
		}
	}

	if (alt_mix > 0.0) {  // second texture in patches, so the tiling doesn't repeat
		vec2 a_uv = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * UV / alt_tile_m;
		float w = smoothstep(1.0 - alt_mix - 0.08, 1.0 - alt_mix + 0.08, fbm(UV / 19.0 + 3.1));
		alb = mix(alb, texture(alt_albedo, a_uv).rgb * tint, w);
		arm = mix(arm, texture(alt_arm, a_uv).rgb, w);
		nrm = mix(nrm, texture(alt_normal, a_uv).rgb, w);
		rough = arm.g;
	}

	if (patch_amount > 0.0 && COLOR.a > 0.5) {  // repaired patches: darker, smoother rectangles along the strip
		vec2 cell = floor(vec2(across / 3.0, along / 6.0));
		vec2 inside = fract(vec2(across / 3.0, along / 6.0));
		float rect = step(0.12, inside.x) * step(inside.x, 0.88) * step(0.1, inside.y) * step(inside.y, 0.9);
		float p = step(hash(cell + 5.3), patch_amount) * rect;
		alb = mix(alb, alb * 0.55, p);
		rough = mix(rough, rough * 0.8, p);
	}

	if (crack_amount > 0.0) {  // cracks, some with weeds
		float region = step(1.0 - crack_amount, fbm(UV / 11.0 + 1.7));
		float c = (1.0 - smoothstep(0.015, 0.045, crack_dist(UV / 2.2))) * region;
		alb = mix(alb, alb * 0.3, c);
		nrm = mix(nrm, vec3(0.5, 0.5, 0.85), c * 0.6);
		float weeds = c * step(1.0 - weed_amount, vnoise(UV * 0.6 + 4.4));
		alb = mix(alb, weed_color * (0.65 + 0.7 * vnoise(UV * 11.0)), weeds);
		rough = mix(rough, 0.95, c);
	}

	if (pothole_amount > 0.0) {  // potholes: gravel showing through, a dark broken rim
		vec2 pc = floor(UV / 7.0);
		vec2 centre = (pc + 0.2 + 0.6 * vec2(hash(pc + 2.1), hash(pc + 8.7))) * 7.0;
		float r = 0.35 + 0.5 * hash(pc + 4.4);
		float d = length(UV - centre) / r + (vnoise(UV * 3.0) - 0.5) * 0.5;
		float on = step(hash(pc + 11.9), pothole_amount);
		float hole = (1.0 - smoothstep(0.85, 1.0, d)) * on;
		float rim = (smoothstep(0.75, 1.0, d) - smoothstep(1.0, 1.25, d)) * on;
		vec2 e_uv = UV / edge_tile_m;
		alb = mix(alb, texture(edge_albedo, e_uv).rgb * 0.55, hole);
		nrm = mix(nrm, texture(edge_normal, e_uv).rgb, hole);
		rough = mix(rough, 0.95, hole);
		alb *= 1.0 - 0.45 * rim;
	}

	float dirt = 0.0;  // dirt drifted in from the edges and in scattered patches
	if (edge_dirt_m > 0.0 && COLOR.a > 0.5) {
		float half_w = COLOR.b * 16.0;
		float reach = edge_dirt_m * (0.4 + 1.2 * fbm(vec2(along * 0.25, across > 0.0 ? 3.0 : 9.0)));
		dirt = smoothstep(half_w - reach, half_w - reach * 0.2, abs(across));
	}
	if (drift_amount > 0.0) {
		dirt = max(dirt, smoothstep(1.0 - drift_amount - 0.05, 1.0 - drift_amount + 0.05, fbm(UV / 6.0 + 21.0)));
	}

	float paint = 0.0;
	vec3 paint_col = white;
	if (COLOR.a > 0.5) {
		if (COLOR.r > 0.75) {
			paint = max(band(across, -0.12, 0.05), band(across, 0.12, 0.05));
			paint_col = yellow;
		} else if (COLOR.r > 0.25) {
			paint = band(across, 0.0, 0.06) * step(fract(along / 12.0), 0.25);
			paint_col = yellow;
		}
		float lanes = floor(COLOR.g * 4.0 + 0.5);
		if (lanes > 1.0) {
			float lane_w = COLOR.b * 16.0 / lanes;
			float side = abs(across) / lane_w;
			float k = floor(side + 0.5);
			if (k >= 1.0 && k < lanes) {
				float w = band(abs(across), k * lane_w, 0.06) * step(fract(along / 12.0), 0.25);
				if (w > paint) {
					paint = w;
					paint_col = white;
				}
			}
		}
		float wear = texture(albedo_tex, uv * 0.37 + 0.21).r;
		paint *= smoothstep(line_wear - 0.08, line_wear + 0.08, wear);
	}
	alb = mix(alb, paint_col * (0.7 + 0.3 * alb.r), paint);
	rough = mix(rough, 0.6, paint);
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), paint);

	if (dirt > 0.0) {  // over the paint: drifted dirt covers lines too
		vec2 e_uv = UV / edge_tile_m;
		vec3 e_alb = texture(edge_albedo, e_uv).rgb;
		float w = clamp(dirt + (dot(e_alb, vec3(0.33)) - 0.5) * 0.3, 0.0, 1.0);
		alb = mix(alb, e_alb, w);
		nrm = mix(nrm, texture(edge_normal, e_uv).rgb, w);
		rough = mix(rough, texture(edge_arm, e_uv).g, w);
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	AO = arm.r;
	NORMAL_MAP = nrm;
}
