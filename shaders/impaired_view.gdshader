// Impaired view (D-082): double vision (a drifting ghost copy of the screen, double_px apart) and blurred edges
// (blur 0-1, from the screen's mipmaps). Drawn by ActiveEffects on a full-screen rect under the HUD, and only while
// one of them is above zero, so it costs nothing sober.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float double_px = 0.0;
uniform float blur = 0.0;
uniform float phase = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 off = vec2(cos(phase * 0.7), sin(phase * 0.9) * 0.6) * double_px * SCREEN_PIXEL_SIZE;
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;
	if (double_px > 0.5) {
		col = mix(col, textureLod(screen_tex, uv + off, 0.0).rgb, 0.42);
	}
	if (blur > 0.01) {
		float edge = smoothstep(0.18, 0.62, distance(uv, vec2(0.5)));
		vec3 soft = textureLod(screen_tex, uv + off * 0.5, 1.5 + blur * 2.5).rgb;
		col = mix(col, soft, clamp(edge * blur * 1.7 + blur * 0.25, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
