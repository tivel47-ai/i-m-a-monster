shader_type canvas_item;
render_mode unshaded;

uniform float motion_time;
uniform float bend = 18.0;
uniform float flexible_height = 310.0;

void vertex() {
	// Sprite origins sit at ground level. The roots and lower trunk stay still.
	float influence = smoothstep(12.0, flexible_height, -VERTEX.y);
	vec2 origin = MODEL_MATRIX[3].xy;
	float gust = sin(motion_time * 1.45 + origin.x * 0.011 + origin.y * 0.007);
	float flutter = sin(motion_time * 3.8 - origin.x * 0.019 + origin.y * 0.016);
	VERTEX.x += influence * bend * (gust * 0.76 + flutter * 0.24);
}
