// Disc tracer (D-076): a see-through white ribbon along a thrown disc's path, always facing the camera and never
// thinner than px_width x distance so it reads from far away. Mesh from DiscTracer: two vertices per path sample at
// the same point, NORMAL = path direction, UV.x = 0..1 along the path (= flight time), UV.y = -1 / +1 side.
// `progress` reveals it as the disc flies.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float progress = 1.0;
uniform float width = 0.04;
uniform float px_width = 0.0018;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.5);

varying float along;

void vertex() {
	along = UV.x;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - wp;
	float d = max(length(to_cam), 0.001);
	vec3 side = cross(tangent, to_cam / d);
	float sl = length(side);
	side = sl > 0.001 ? side / sl : vec3(0.0, 1.0, 0.0);
	wp += side * max(width, d * px_width) * UV.y;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

void fragment() {
	if (along > progress) {
		discard;
	}
	float start = smoothstep(0.0, 0.06, along);
	float edge = 1.0 - smoothstep(0.4, 1.0, abs(UV.y));
	ALBEDO = color.rgb;
	ALPHA = color.a * start * edge;
}
