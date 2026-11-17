shader_type canvas_item;
render_mode unshaded;

uniform float aspect;
uniform vec2 content_scale = vec2(1.0);
uniform bool preview = false;
uniform int clearing_count = 0;
// Each clearing stores its center in height units, radius, and influence.
uniform vec4 clearings[40];
uniform vec4 pulses[4];

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
	vec2 art_uv = (UV - 0.5) / content_scale + 0.5;
	vec2 sample_uv = clamp(art_uv, vec2(0.0), vec2(1.0));
	vec2 point = art_uv * vec2(aspect, 1.0);
	float inside = min(min(art_uv.x, 1.0 - art_uv.x), min(art_uv.y, 1.0 - art_uv.y));
	float texture_edge = smoothstep(-0.02, 0.055, inside);
	vec3 art = texture(TEXTURE, sample_uv).rgb;
	float pulse = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 glow = pulses[i];
		float rim = length(point - glow.xy);
		pulse += glow.z * (1.0 - smoothstep(0.0, glow.w, rim));
	}
	float fibers = smoothstep(0.10, 0.68, art.g);
	art += vec3(0.58, 0.67, 0.32) * pulse * fibers;

	if (preview) {
		art = mix(vec3(0.102, 0.13, 0.115), art, texture_edge);
	} else {
		vec2 drift = point + vec2(-TIME * 0.027, TIME * 0.011);
		float billow = mist_noise(drift * vec2(3.5, 6.0));
		float wisp = mist_noise(drift * vec2(8.0, 23.0) + billow * 2.1);
		float fringe = mist_noise(drift * vec2(17.0, 39.0) - wisp * 1.3);
		float vapor = 0.56 * billow + 0.32 * wisp + 0.12 * fringe;
		vec2 wandering_edge = point + vec2(billow - 0.5, wisp - 0.5) * 0.059;
		float opening = 0.0;
		for (int i = 0; i < clearing_count; i++) {
			vec4 area = clearings[i];
			float distance_to_center = length(wandering_edge - area.xy);
			float gap = 1.0 - smoothstep(area.z * 0.40, area.z, distance_to_center);
			opening = max(opening, gap * area.w);
		}
		vec3 mist = mix(vec3(0.067, 0.082, 0.076), vec3(0.40, 0.45, 0.419), vapor);
		// Low-frequency shadows hint at shapes under the fog without exposing emblems.
		float shadow = 1.0 - smoothstep(0.065, 0.245, textureLod(TEXTURE, sample_uv, 5.0).g);
		vec3 shrouded = mist - 0.072 * shadow * texture_edge * (1.0 - vapor);
		art = mix(shrouded, art, texture_edge * opening * (1.0 - 0.20 * vapor));
	}
	float vignette = smoothstep(0.26, 0.71, length((UV - 0.5) * vec2(0.92, 0.88)));
	COLOR = vec4(art * (1.0 - vignette * 0.31), 1.0);
}
