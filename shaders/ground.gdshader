// Ground — terrain of the generated map (D-043, layers D-115). Base: the dry-grass photo texture tiled in world
// metres, blended with a second rotated, larger copy and a slow brightness drift so the tiling doesn't show.
// Layers on top (D-115): a dirtier grass (grass2_*) in broad patches, bare dirt (dirt_*) in smaller patches and
// on steep slopes; each layer's edge is broken up by noise and by the texture's own detail so it doesn't read as
// a soft blob. No vertex data needed - patches come from world-space noise, slope from the normal - so existing
// cells pick it up without a re-bake.
// Far away (D-120) the 3 m tiles still showed as a grid: past far_start_m the base fades into a much larger,
// rotated copy (far_tile_mult x tile_m), and broad colour / brightness patches (macro_m across) break up the
// distance so no repeat is left to read.
// Mesh contract (written by tools/map_import/build_cells.gd): UV = world (x, z) in metres.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 3.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float variation = 0.25;  // strength of the large-scale brightness drift

uniform sampler2D grass2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass2_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass2_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass2_tile_m = 4.0;
uniform float dirt_tile_m = 3.0;
uniform float grass2_amount = 0.0;  // 0..1 share of open ground in the dirtier grass (0 = layer off)
uniform float dirt_amount = 0.0;    // 0..1 share of open ground as bare dirt (0 = layer off)
uniform float patch_m = 24.0;       // typical patch size, metres
uniform float slope_dirt = 0.3;     // ground steeper than this (1 - normal.y) turns to dirt
uniform vec3 layer_tint : source_color = vec3(1.0);
uniform float far_start_m = 20.0;   // D-120 distance where the large copy starts to take over
uniform float far_end_m = 90.0;     // ... and where it reaches far_amount
uniform float far_tile_mult = 7.0;
uniform float far_amount = 0.8;
uniform float macro_m = 70.0;       // size of the broad colour patches
uniform float macro = 0.16;         // their brightness swing
uniform float macro_hue = 0.12;     // how far they lean yellow-dry vs greener

varying float v_up;

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

// Edge of a layer: `n` is the patch noise, `share` how much ground it covers, `detail` the texture's own
// brightness so the border follows clumps and stones instead of a smooth curve.
float layer_mask(float n, float share, float detail) {
	float t = 1.0 - share;
	return smoothstep(t - 0.04, t + 0.04, n + (detail - 0.5) * 0.18);
}

void vertex() {
	v_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	vec2 uv_a = UV / tile_m;
	vec2 uv_b = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * UV / (tile_m * 2.7);
	float blend = texture(albedo_tex, UV / (tile_m * 41.0)).g;
	blend = smoothstep(0.3, 0.7, blend);
	vec3 alb = mix(texture(albedo_tex, uv_a).rgb, texture(albedo_tex, uv_b).rgb, blend);
	vec3 arm = mix(texture(arm_tex, uv_a).rgb, texture(arm_tex, uv_b).rgb, blend);
	vec3 nrm = mix(texture(normal_tex, uv_a).rgb, texture(normal_tex, uv_b).rgb, blend);
	float drift = texture(albedo_tex, UV / (tile_m * 97.0) + 0.5).r;
	alb *= tint * (1.0 - variation * 0.5 + variation * drift * 2.0);
	float far = smoothstep(far_start_m, far_end_m, length(VERTEX)) * far_amount;
	if (far > 0.0) {
		vec2 uv_f = mat2(vec2(0.28, 0.96), vec2(-0.96, 0.28)) * UV / (tile_m * far_tile_mult) + 0.37;
		alb = mix(alb, texture(albedo_tex, uv_f).rgb * tint, far);
		arm = mix(arm, texture(arm_tex, uv_f).rgb, far);
		nrm = mix(nrm, texture(normal_tex, uv_f).rgb, far);
	}
	float m1 = fbm(UV / macro_m + 11.3);
	float m2 = fbm(UV / (macro_m * 1.7) + 57.1);
	alb *= 1.0 - macro + m1 * macro * 2.0;
	alb = mix(alb, alb * vec3(1.06, 1.0, 0.82), clamp((m2 - 0.5) * 2.0, 0.0, 1.0) * macro_hue * 4.0);
	alb = mix(alb, alb * vec3(0.9, 1.04, 0.92), clamp((0.5 - m2) * 2.0, 0.0, 1.0) * macro_hue * 4.0);

	if (grass2_amount > 0.0) {
		vec2 g_uv = mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * UV / grass2_tile_m;
		vec3 g_alb = texture(grass2_albedo, g_uv).rgb * layer_tint;
		float w = layer_mask(fbm(UV / patch_m), grass2_amount, dot(g_alb, vec3(0.33)));
		alb = mix(alb, g_alb, w);
		arm = mix(arm, texture(grass2_arm, g_uv).rgb, w);
		nrm = mix(nrm, texture(grass2_normal, g_uv).rgb, w);
	}
	if (dirt_amount > 0.0) {
		vec2 d_uv = UV / dirt_tile_m;
		vec3 d_alb = texture(dirt_albedo, d_uv).rgb * layer_tint;
		float n = fbm(UV / (patch_m * 0.45) + 31.7);
		float steep = smoothstep(slope_dirt, slope_dirt + 0.12, 1.0 - v_up);
		float w = max(layer_mask(n, dirt_amount, dot(d_alb, vec3(0.33))), steep);
		alb = mix(alb, d_alb, w);
		arm = mix(arm, texture(dirt_arm, d_uv).rgb, w);
		nrm = mix(nrm, texture(dirt_normal, d_uv).rgb, w);
	}
	ALBEDO = alb;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
	AO = arm.r;
	NORMAL_MAP = nrm;
}
