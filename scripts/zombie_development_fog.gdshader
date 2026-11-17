shader_type canvas_item;
render_mode unshaded;

uniform float aspect;
uniform vec2 content_scale = vec2(1.0);
uniform vec2 content_origin = vec2(0.0);
uniform bool preview = false;
uniform int branch_segment_count = 0;
// Branch segments store two endpoints. The style stores radius and opacity.
uniform vec4 branch_segments[64];
uniform vec2 branch_styles[64];
// Each node stores its position, silhouette strength, and activation light.
uniform vec4 node_spots[10];
uniform vec4 pulses[11];

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
	return mix(
		mix(grain(cell), grain(cell + vec2(1.0, 0.0)), step_uv.x),
		mix(grain(cell + vec2(0.0, 1.0)), grain(cell + vec2(1.0)), step_uv.x),
		step_uv.y
	);
}

void fragment() {
	vec2 art_uv = (UV - content_origin) / content_scale;
	vec2 sample_uv = clamp(art_uv, vec2(0.0), vec2(1.0));
	vec2 point = art_uv * vec2(aspect, 1.0);
	float inside = min(min(art_uv.x, 1.0 - art_uv.x), min(art_uv.y, 1.0 - art_uv.y));
	float texture_edge = smoothstep(-0.02, 0.055, inside);
	vec3 art = texture(TEXTURE, sample_uv).rgb;
	float pulse = 0.0;
	for (int i = 0; i < 11; i++) {
		vec4 glow = pulses[i];
		float rim = length(point - glow.xy);
		pulse += glow.z * (1.0 - smoothstep(0.0, glow.w, rim));
	}
	float fibers = smoothstep(0.10, 0.68, art.g);
	art += vec3(0.58, 0.67, 0.32) * pulse * fibers;

	float drift_time = preview ? 0.0 : TIME;
	vec2 drift = point + vec2(-drift_time * 0.027, drift_time * 0.011);
	float billow = mist_noise(drift * vec2(3.5, 6.0));
	float wisp = mist_noise(drift * vec2(8.0, 23.0) + billow * 2.1);
	float fringe = mist_noise(drift * vec2(17.0, 39.0) - wisp * 1.3);
	float vapor = 0.56 * billow + 0.32 * wisp + 0.12 * fringe;
	vec2 contour = point + vec2(billow - 0.5, wisp - 0.5) * 0.017;
	vec3 mist = mix(vec3(0.067, 0.082, 0.076), vec3(0.40, 0.45, 0.419), vapor);
	float opening = 0.0;
	for (int i = 0; i < branch_segment_count; i++) {
		vec4 segment = branch_segments[i];
		vec2 style = branch_styles[i];
		vec2 line = segment.zw - segment.xy;
		float along = clamp(dot(contour - segment.xy, line) / max(dot(line, line), 0.000001), 0.0, 1.0);
		float distance_to_branch = length(contour - segment.xy - line * along);
		opening = max(opening, style.y * (1.0 - smoothstep(style.x * 0.5, style.x, distance_to_branch)));
	}
	float distance_to_core = length((contour - vec2(aspect * 0.50, 0.474)) * vec2(1.0, 1.11));
	opening = max(opening, 1.0 - smoothstep(0.159, 0.252, distance_to_core));
	float haze = preview ? 1.0 : 1.0 - 0.17 * vapor;
	// Hide unused painted branches entirely; only actual dependency routes open.
	float buried = textureLod(TEXTURE, sample_uv, 3.2).g;
	vec3 shroud = mist;
	vec3 result = mix(shroud, art, texture_edge * opening * haze);
	for (int i = 0; i < 3; i++) {
		vec4 node = node_spots[i];
		float distance_to_node = length(contour - node.xy);
		if (distance_to_node < 0.108) {
			float patch = 1.0 - smoothstep(0.057, 0.108, distance_to_node);
			// Neighboring dark fibers bridge the light emblem while retaining the painted outline.
			vec2 offset = vec2(0.016 / aspect, 0.016);
			float fibers_x = min(
				textureLod(TEXTURE, sample_uv + vec2(offset.x, 0.0), 2.5).g,
				textureLod(TEXTURE, sample_uv - vec2(offset.x, 0.0), 2.5).g);
			float fibers_y = min(
				textureLod(TEXTURE, sample_uv + vec2(0.0, offset.y), 2.5).g,
				textureLod(TEXTURE, sample_uv - vec2(0.0, offset.y), 2.5).g);
			float shape = 1.0 - smoothstep(0.085, 0.25, min(buried, min(fibers_x, fibers_y)));
			float center = 1.0 - smoothstep(0.027, 0.051, distance_to_node);
			float darkness = max(center * 0.74, shape) * mix(0.12, 0.43, node.z);
			vec3 node_color = mix(mist * (1.0 - darkness), art, node.w);
			result = mix(result, node_color, texture_edge * patch * haze);
		}
	}
	float vignette = smoothstep(0.26, 0.71, length((UV - 0.5) * vec2(0.92, 0.88)));
	COLOR = vec4(result * (1.0 - vignette * 0.31), 1.0);
}
