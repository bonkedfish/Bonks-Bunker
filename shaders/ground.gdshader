// Ground — terrain of the generated map (D-043): the grass photo texture tiled in world metres, blended with
// a second, rotated, larger copy and a slow brightness drift so the tiling doesn't show across open ground.
// Mesh contract (written by tools/map_import/build_cells.gd): UV = world (x, z) in metres.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 3.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float variation = 0.25;  // strength of the large-scale brightness drift

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
	ALBEDO = alb;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
	AO = arm.r;
	NORMAL_MAP = nrm;
}
