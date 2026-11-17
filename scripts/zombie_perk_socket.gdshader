shader_type canvas_item;
render_mode unshaded;

uniform float turn = 0.0;

void fragment() {
	vec2 local = UV - vec2(0.5);
	float radius = length(local);
	mat2 rotation = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn)));
	vec2 sample_uv = rotation * local + vec2(0.5);
	// Reuse the original painted bark around Tough Flesh. Hide its old emblem
	// beneath the dark center; the shared NODES icon is drawn above this socket.
	vec2 art_uv = vec2(399.0, 174.0) / vec2(1672.0, 941.0)
		+ sample_uv * vec2(168.0, 168.0) / vec2(1672.0, 941.0);
	vec3 bark = texture(TEXTURE, art_uv).rgb;
	float edge = 0.46 + 0.025 * sin(atan(local.y, local.x) * 13.0);
	float mask = 1.0 - smoothstep(edge - 0.10, edge, radius);
	float rim = smoothstep(0.24, 0.37, radius);
	vec3 color = mix(vec3(0.060, 0.067, 0.050), bark, rim);
	COLOR = vec4(color, mask);
}
