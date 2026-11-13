// Outfit — dresses a plain Quaternius base body (D-058) by skin weights: each vertex is coloured by the bone that
// moves it most (torso/arms = shirt, pelvis/legs = pants, feet = shoes, head/neck/hands = skin), keeping the body
// texture's shading as cloth detail. Bone indices follow the Universal rig order (65 bones).
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec3 skin_color : source_color = vec3(0.78, 0.6, 0.48);
uniform vec3 shirt_color : source_color = vec3(0.3, 0.32, 0.22);
uniform vec3 pants_color : source_color = vec3(0.2, 0.24, 0.32);
uniform vec3 shoes_color : source_color = vec3(0.12, 0.1, 0.08);
uniform float cloth_detail = 0.6;

varying vec4 region; // skin, shirt, pants, shoes

vec4 region_of(uint b) {
	if (b == 2u || b == 3u || b == 4u || b == 7u || b == 8u || b == 9u || b == 31u || b == 32u || b == 33u) {
		return vec4(0.0, 1.0, 0.0, 0.0);
	}
	if (b == 1u || b == 55u || b == 56u || b == 60u || b == 61u) {
		return vec4(0.0, 0.0, 1.0, 0.0);
	}
	if ((b >= 57u && b <= 59u) || (b >= 62u && b <= 64u)) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	return vec4(1.0, 0.0, 0.0, 0.0);
}

void vertex() {
	uint best = BONE_INDICES.x;
	float w = BONE_WEIGHTS.x;
	if (BONE_WEIGHTS.y > w) { best = BONE_INDICES.y; w = BONE_WEIGHTS.y; }
	if (BONE_WEIGHTS.z > w) { best = BONE_INDICES.z; w = BONE_WEIGHTS.z; }
	if (BONE_WEIGHTS.w > w) { best = BONE_INDICES.w; }
	region = region_of(best);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	float shade = mix(1.0, clamp(lum / 0.35, 0.4, 1.4), cloth_detail);
	vec3 col = region.x * skin_color * mix(1.0, clamp(lum / 0.3, 0.6, 1.3), 0.5)
		+ region.y * shirt_color * shade
		+ region.z * pants_color * shade
		+ region.w * shoes_color * shade;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.6, region.x);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
