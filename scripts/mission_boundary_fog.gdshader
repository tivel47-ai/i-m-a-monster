shader_type canvas_item;
render_mode unshaded;

uniform vec2 map_start;
uniform vec2 map_end;
uniform float fog_width;
uniform float motion_time;

varying vec2 map_position;

float hash_cell(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float cloud_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(
		mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), blend.x),
		blend.y
	);
}

void vertex() {
	map_position = VERTEX;
}

void fragment() {
	vec2 edge = min(map_position - map_start, map_end - map_position);
	float distance_to_edge = min(edge.x, edge.y);
	vec2 flow = (map_position - map_start) * vec2(0.007, 0.009);
	float billow = cloud_noise(flow - motion_time * vec2(0.11, 0.07));
	float curls = cloud_noise(flow * 2.2 + vec2(13.1, 7.2) - motion_time * vec2(0.19, -0.13));
	float wisps = cloud_noise(flow * 4.7 + vec2(-6.0, 12.0) - motion_time * vec2(0.34, 0.13));
	float density = smoothstep(0.18, 0.82, billow * 0.55 + curls * 0.32 + wisps * 0.13);
	float reach = fog_width * mix(0.42, 1.0, density);
	float bank = 1.0 - smoothstep(0.0, reach, distance_to_edge);
	float veil = 1.0 - smoothstep(0.0, fog_width, distance_to_edge);
	vec3 tint = mix(vec3(0.41, 0.46, 0.46), vec3(0.63, 0.68, 0.67), density);
	COLOR = vec4(tint, bank * mix(0.31, 0.72, density) + veil * 0.08);
}
