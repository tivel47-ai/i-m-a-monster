shader_type canvas_item;
render_mode unshaded;

uniform float aspect;
uniform vec2 content_scale = vec2(1.0);
uniform vec2 content_origin = vec2(0.0);
uniform bool overlay_pass = false;
uniform float mist_time = 0.0;
uniform sampler2D reveal_sites : filter_nearest, repeat_disable;
uniform int reveal_count = 0;
uniform sampler2D root_clearance : filter_linear, repeat_disable;
uniform vec2 root_mask_padding = vec2(0.24);
uniform vec2 root_mask_extent = vec2(2.2568, 1.48);

float grain(vec2 cell) {
	uvec2 coords = uvec2(ivec2(cell));
	uint bits = coords.x * 374761393u + coords.y * 668265263u;
	bits = (bits ^ (bits >> 13u)) * 1274126177u;
	return float((bits ^ (bits >> 16u)) & 65535u) / 65535.0;
}

float mist_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 step_uv = fract(point);
	step_uv = step_uv * step_uv * (3.0 - 2.0 * step_uv);
	return mix(mix(grain(cell), grain(cell + vec2(1.0, 0.0)), step_uv.x),
		mix(grain(cell + vec2(0.0, 1.0)), grain(cell + vec2(1.0)), step_uv.x), step_uv.y);
}

void fragment() {
	// Art and atmosphere are separate; there is no baked painting underneath.
	vec2 point = (UV - content_origin) / content_scale * vec2(aspect, 1.0);
	float drift_time = mist_time;
	vec2 drift = point + vec2(-drift_time * 0.027, drift_time * 0.011);
	float billow = mist_noise(drift * vec2(3.5, 6.0));
	float wisp = mist_noise(drift * vec2(8.0, 23.0) + billow * 2.1);
	float fringe = mist_noise(drift * vec2(17.0, 39.0) - wisp * 1.3);
	float vapor = 0.56 * billow + 0.32 * wisp + 0.12 * fringe;
	vec3 mist = mix(vec3(0.067, 0.082, 0.076), vec3(0.40, 0.45, 0.419), vapor);
	float vignette = smoothstep(0.26, 0.71, length((UV - 0.5) * vec2(0.92, 0.88)));
	if (!overlay_pass) {
		// Exposed ground must differ from the moving death fog above it.
		float ground_grain = mist_noise(point * vec2(4.0, 5.0));
		vec3 ground = mix(vec3(0.092, 0.118, 0.096), vec3(0.145, 0.170, 0.136), ground_grain);
		COLOR = vec4(ground * (1.0 - vignette * 0.31), 1.0);
	} else {
		// The central infection is always visible. Each unlocked territory is
		// intersected with an expanding wave from its source, never faded in
		// uniformly. A texture supplies sites without a fixed node-count limit.
		vec2 core = vec2(aspect * 0.5, 0.474);
		float field = (length((point - core) / vec2(0.27, 0.21)) - 1.0) * 0.21;
		for (int i = 0; i < reveal_count; i++) {
			float u = (float(i) + 0.5) / float(reveal_count);
			vec4 ends = texture(reveal_sites, vec2(u, 0.25));
			vec4 state = texture(reveal_sites, vec2(u, 0.75));
			if (state.a < 0.5 || state.r <= 0.0) { continue; }
			// Connections clear along their real curved route in root_clearance.
			float territory = length(point - ends.zw) - state.g;
			float wave = length(point - ends.xy) - state.r;
			field = min(field, max(territory, wave));
		}
		// Moving wisps displace the contour, rather than just sliding a noise
		// pattern across a stationary circular hole.
		float ripple = (billow - 0.5) * 0.045 + (wisp - 0.5) * 0.027 + (fringe - 0.5) * 0.012;
		float density = smoothstep(-0.045, 0.045, field + ripple);
		vec2 wavering_point = point + vec2((wisp - 0.5) * 0.018, (fringe - 0.5) * 0.018);
		// Padding prevents the clearing from ending in a straight canvas edge.
		vec2 local_uv = (wavering_point + root_mask_padding) / root_mask_extent;
		if (all(greaterThanEqual(local_uv, vec2(0.0))) && all(lessThanEqual(local_uv, vec2(1.0)))) {
			// The mask follows the real curved root, including its painted width.
			density *= 1.0 - texture(root_clearance, local_uv).a;
		}
		float rim = 1.0 - smoothstep(0.0, 0.075, abs(field));
		vec3 haze = mist * 0.84 + vec3(0.055, 0.066, 0.055) * rim * wisp;
		COLOR = vec4(haze, density * 0.98);
	}
}
