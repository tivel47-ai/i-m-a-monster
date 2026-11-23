shader_type canvas_item;
render_mode unshaded;

varying vec2 offset_from_flue;
varying float opacity;

void vertex() {
	offset_from_flue = VERTEX;
	opacity = COLOR.a;
}

void fragment() {
	vec2 point = floor(offset_from_flue / 3.5) * 3.5;
	float smoke = 0.0;
	for (int i = 0; i < 7; i++) {
		float seed = float(i);
		float age = fract(TIME * 0.27 + seed / 7.0);
		float shift = 54.0 * age + 67.0 * age * age;
		shift += 11.0 * age * sin(TIME * 1.2 + seed * 2.4);
		vec2 center = vec2(shift, -183.0 * age);
		vec2 radius = mix(vec2(10.0, 11.0), vec2(48.0, 35.0), age);
		vec2 sample_point = (point - center) / radius;
		float clumps = 0.14 * sin(sample_point.x * 8.0 + seed)
			* sin(sample_point.y * 10.0 + TIME + seed);
		float density = 1.0 - smoothstep(0.42, 1.07, length(sample_point) + clumps);
		float life = smoothstep(0.0, 0.11, age) * (1.0 - smoothstep(0.23, 1.0, age));
		smoke = max(smoke, density * life);
	}
	float flue_edge = 1.0 - smoothstep(-5.0, 7.0, offset_from_flue.y);
	vec3 ash = mix(vec3(0.57, 0.58, 0.56), vec3(0.76, 0.74, 0.68), smoke);
	COLOR = vec4(ash, smoke * flue_edge * opacity * 0.64);
}
