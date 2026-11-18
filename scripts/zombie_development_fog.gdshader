shader_type canvas_item;
render_mode unshaded;

uniform float aspect;
uniform vec2 content_scale = vec2(1.0);
uniform vec2 content_origin = vec2(0.0);
uniform bool preview = false;

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
	// Background contains only mist, never the old painting or its stray roots.
	vec2 point = (UV - content_origin) / content_scale * vec2(aspect, 1.0);
	float drift_time = preview ? 0.0 : TIME;
	vec2 drift = point + vec2(-drift_time * 0.027, drift_time * 0.011);
	float billow = mist_noise(drift * vec2(3.5, 6.0));
	float wisp = mist_noise(drift * vec2(8.0, 23.0) + billow * 2.1);
	float fringe = mist_noise(drift * vec2(17.0, 39.0) - wisp * 1.3);
	float vapor = 0.56 * billow + 0.32 * wisp + 0.12 * fringe;
	vec3 mist = mix(vec3(0.067, 0.082, 0.076), vec3(0.40, 0.45, 0.419), vapor);
	float vignette = smoothstep(0.26, 0.71, length((UV - 0.5) * vec2(0.92, 0.88)));
	COLOR = vec4(mist * (1.0 - vignette * 0.31), 1.0);
}
