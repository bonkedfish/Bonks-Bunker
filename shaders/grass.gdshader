// Grass — the 3D grass clumps near the camera (D-115, GrassField). Blade geometry comes from the mesh (UV.y = 0
// at the root .. 1 at the tip, COLOR = root-to-tip colour); the MultiMesh instance colour tints each clump.
// Blades shrink to nothing between fade_start_m and fade_end_m from the camera, so chunks never pop, and sway in
// a slow wind (more at the tip). Lit as if facing up, like the ground they stand on. No shadows (set on the node).
shader_type spatial;
render_mode cull_disabled;

uniform float fade_start_m = 30.0;
uniform float fade_end_m = 45.0;
uniform float wind_m = 0.06;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = 1.0 - smoothstep(fade_start_m, fade_end_m, distance(root, CAMERA_POSITION_WORLD));
	VERTEX.y *= k;
	float tip = UV.y * UV.y;
	float t = TIME * 1.6 + root.x * 0.31 + root.z * 0.23;
	VERTEX.x += sin(t) * wind_m * tip;
	VERTEX.z += sin(t * 0.83 + 1.7) * wind_m * 0.6 * tip;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	AO = mix(0.45, 1.0, UV.y);
}
