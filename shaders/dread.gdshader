// Dread overlay (D-114): desaturates the screen and closes in a dark-red vignette while a zombie has you.
// Drawn by Dread's ColorRect only while it's active (hidden otherwise, so it costs nothing).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.0;
uniform float desaturate = 0.0;
uniform vec3 edge_color : source_color = vec3(0.12, 0.0, 0.0);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g), desaturate);
	float v = smoothstep(0.3, 0.95, length((SCREEN_UV - 0.5) * vec2(1.25, 1.0)) * 1.5);
	c = mix(c, edge_color, v * vignette);
	COLOR = vec4(c, 1.0);
}
