shader_type canvas_item;
render_mode unshaded;

uniform sampler2D fog_texture : source_color, filter_linear, repeat_disable;
uniform vec2 canvas_size = vec2(1280.0, 720.0);
uniform vec4 map_frame = vec4(0.0, 0.0, 1.0, 1.0);
uniform float reveal : hint_range(0.0, 1.0) = 0.0;

float cloud_hash(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float cloud_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(cloud_hash(cell), cloud_hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(cloud_hash(cell + vec2(0.0, 1.0)), cloud_hash(cell + 1.0), blend.x), blend.y);
}

float cell_edge(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	float nearest = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 neighbor = cell + offset;
			vec2 seed = vec2(cloud_hash(neighbor), cloud_hash(neighbor + vec2(19.2, 61.4)));
			vec2 delta = offset + 0.12 + seed * 0.76 - local;
			float distance_squared = dot(delta, delta);
			second = min(second, max(nearest, distance_squared));
			nearest = min(nearest, distance_squared);
		}
	}
	return sqrt(second) - sqrt(nearest);
}

void fragment() {
	vec2 texture_size = vec2(textureSize(fog_texture, 0));
	float aspect = canvas_size.x / canvas_size.y;
	float texture_aspect = texture_size.x / texture_size.y;
	vec2 crop = min(vec2(aspect / texture_aspect, texture_aspect / aspect), vec2(1.0));
	vec2 drift = vec2(sin(TIME * 0.21), cos(TIME * 0.17)) * 0.018;
	vec2 fog_uv = (UV - 0.5) * crop * 0.94 + 0.5 + drift;
	vec3 fog = texture(fog_texture, fog_uv).rgb * vec3(0.78, 0.82, 0.80);
	COLOR = vec4(fog, 1.0);

	if (reveal > 0.0) {
		vec2 map_uv = (UV * canvas_size - map_frame.xy) / map_frame.zw;
		vec2 edge = min(map_uv, 1.0 - map_uv);
		float edge_distance = min(edge.x, edge.y);
		if (edge_distance > -0.055) {
			vec2 map_aspect = map_frame.zw / min(map_frame.z, map_frame.w);
			vec2 point = (map_uv - 0.5) * map_aspect;
			vec2 flow = point + drift * 1.4;
			float billow = cloud_noise(flow * vec2(7.0, 9.0));
			float wisps = cloud_noise(flow * vec2(19.0, 27.0) + billow);
			float fringe = cloud_noise(flow * vec2(43.0, 47.0) - wisps * 0.65);
			float roughness = (billow - 0.5) * 0.24 + (wisps - 0.5) * 0.14 + (fringe - 0.5) * 0.045;
			// A rounded, irregular clearing stays within the captured terrain.
			vec2 rounded = pow(abs(2.0 * map_uv - 1.0), vec2(5.0));
			float bank = pow(rounded.x + rounded.y, 0.2) + roughness;
			float perimeter = (1.0 - smoothstep(0.79, 1.01, bank))
				* smoothstep(0.004, 0.039, edge_distance);
			float wave = mix(-0.10, length(map_aspect) * 0.5 + 0.14, reveal);
			float front = length(point) + roughness * 0.65 - wave;
			float clearing = perimeter * (1.0 - smoothstep(-0.066, 0.055, front));
			float rim = smoothstep(0.05, 0.35, clearing) * (1.0 - smoothstep(0.4, 0.97, clearing));
			vec3 haze = fog * (1.0 + rim * 0.38) + vec3(0.12, 0.14, 0.09) * rim * wisps;

			// Broken clusters follow both the moving front and the settled bank.
			float seam = max((bank - 0.945) * 0.45, front);
			float vein_band = smoothstep(-0.032, -0.008, seam) * (1.0 - smoothstep(0.012, 0.044, seam));
			float clusters = smoothstep(0.43, 0.65, billow * 0.70 + wisps * 0.30);
			float vein_mask = vein_band * clusters * smoothstep(0.48, 0.91, 1.0 - clearing)
				* smoothstep(-0.055, -0.031, edge_distance);
			float vein_alpha = 0.0;
			if (vein_mask > 0.0) {
				vec2 warp = vec2(billow, wisps) * 1.55 + vec2(fringe, -fringe) * 0.78;
				float line = cell_edge(flow * 76.0 + warp);
				float core = 1.0 - smoothstep(0.015, 0.108, line);
				float glow = 1.0 - smoothstep(0.044, 0.30, line);
				float breakup = mix(0.17, 1.0, smoothstep(0.27, 0.65, fringe));
				vein_alpha = (core * 0.49 + glow * 0.23) * breakup * vein_mask;
			}
			vec3 vein_tint = vec3(0.53, 0.64, 0.21);
			float haze_alpha = (1.0 - clearing) * (1.0 - vein_alpha);
			float alpha = haze_alpha + vein_alpha;
			COLOR = vec4((haze * haze_alpha + vein_tint * vein_alpha) / max(alpha, 0.001), alpha);
		}
	}
}
