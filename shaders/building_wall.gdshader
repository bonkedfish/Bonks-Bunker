// BuildingWall — walls of generated buildings (D-041 phase 1). Photo texture (albedo/normal/ARM) tiled in metres,
// optional lap-siding lines, and a procedural window grid so no window geometry is needed.
// Mesh contract (written by tools/map_import/build_cells.gd):
//   UV   = (metres along the building outline, metres above the wall base)
//   UV2  = (length of this wall edge in metres, metres along this edge); UV2.x = 0 means "no windows here"
//   COLOR.r = wall height / 64 m, COLOR.g = per-building random 0..1 (tint and window variation)
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 2.5;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_variation = 0.2;
uniform float lap_spacing_m = 0.0;
uniform float recolor = 0.0;  // 0 = photo colours, 1 = painted with paint_a..paint_b (texture keeps its shading)
uniform vec3 paint_a : source_color = vec3(0.86);
uniform vec3 paint_b : source_color = vec3(0.86);
uniform bool windows = true;
uniform float win_spacing = 3.2;
uniform float floor_h = 3.0;
uniform float win_w = 1.1;
uniform float win_h = 1.3;
uniform float sill = 1.2;
uniform float boarded_fraction = 0.25;
uniform float broken_fraction = 0.2;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = vec2(UV.x, -UV.y) / tile_m;
	vec3 alb = texture(albedo_tex, uv).rgb;
	vec3 arm = texture(arm_tex, uv).rgb;
	vec3 nrm = texture(normal_tex, uv).rgb;
	float rnd = COLOR.g;
	if (recolor > 0.0) {
		float lum = dot(alb, vec3(0.299, 0.587, 0.114));
		alb = mix(alb, mix(paint_a, paint_b, rnd) * (0.55 + lum * 1.1), recolor);
	}
	alb *= tint * (1.0 - tint_variation * 0.5 + tint_variation * rnd);
	if (lap_spacing_m > 0.0) {
		float f = fract(UV.y / lap_spacing_m);
		alb *= mix(0.5, 1.0, smoothstep(0.0, 0.3, f));  // shadow under each board's lip
	}
	float rough = arm.g;
	float ao = arm.r;
	float metal = 0.0;

	float wall_h = COLOR.r * 64.0;
	if (windows && UV2.x > 0.0) {
		float n = floor(UV2.x / win_spacing);
		float lu = UV2.y - (UV2.x - n * win_spacing) * 0.5;
		float fl = floor(UV.y / floor_h);
		float cv = UV.y - fl * floor_h - sill;
		bool fits = (fl + 1.0) * floor_h <= wall_h + 0.4;
		if (n >= 1.0 && fits && lu > 0.0 && lu < n * win_spacing) {
			float col = floor(lu / win_spacing);
			float cu = lu - col * win_spacing - win_spacing * 0.5;
			if (abs(cu) < win_w * 0.5 && cv > 0.0 && cv < win_h) {
				float edge = min(win_w * 0.5 - abs(cu), min(cv, win_h - cv));
				float kind = hash(vec2(col + rnd * 97.0, fl + UV2.x * 0.37));
				if (edge < 0.07) {
					alb = vec3(0.75, 0.73, 0.68);  // frame
					rough = 0.7;
				} else if (kind < boarded_fraction) {
					float board = fract(cv / 0.18);
					alb = vec3(0.32, 0.24, 0.17) * mix(0.6, 1.0, smoothstep(0.0, 0.1, board));
					rough = 0.95;
				} else if (kind < boarded_fraction + broken_fraction) {
					alb = vec3(0.01);  // glass gone: dark hole
					rough = 1.0;
				} else {
					alb = vec3(0.03, 0.035, 0.04);
					rough = 0.12;
					metal = 0.3;
				}
				nrm = vec3(0.5, 0.5, 1.0);
				ao = 1.0;
			}
		}
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	AO = ao;
	NORMAL_MAP = nrm;
}
