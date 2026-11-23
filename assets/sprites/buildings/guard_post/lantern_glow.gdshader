shader_type canvas_item;
render_mode blend_add, unshaded;

varying vec2 offset_from_flame;
varying float opacity;

void vertex() {
	offset_from_flame = VERTEX;
	opacity = COLOR.a;
}

void fragment() {
	float flicker = 0.84 + 0.10 * sin(TIME * 5.0) + 0.06 * sin(TIME * 9.1);
	float distance_to_flame = length(offset_from_flame / vec2(45.0, 58.0));
	float halo = pow(max(1.0 - distance_to_flame, 0.0), 2.4);
	float pane = 1.0 - smoothstep(0.55, 1.0, length(offset_from_flame / vec2(11.0, 17.0)));
	COLOR = vec4(1.0, 0.62, 0.22, opacity * flicker * (0.28 * halo + 0.32 * pane));
}
