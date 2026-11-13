// StreetSurface — roads, alleys, driveways, sidewalks and curbs of the generated map (D-043). Photo texture
// (albedo/normal/ARM) tiled in world metres so overlapping strips at intersections match, optional slab joints
// (concrete) and painted lane lines that wear away and stop at intersections.
// Mesh contract (written by tools/map_import/build_cells.gd):
//   UV   = world (x, z) in metres
//   UV2  = (metres across from the strip's centre line, metres along the strip)
//   COLOR.r = centre line: 0 none, 0.5 dashed yellow, 1 double solid yellow
//   COLOR.g = lanes per direction / 4 (white dashed lines between them)
//   COLOR.b = strip half width / 16 m,  COLOR.a = 1 paint lines here, 0 not (intersection)
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

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	AO = arm.r;
	NORMAL_MAP = nrm;
}
