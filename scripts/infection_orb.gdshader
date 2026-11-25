shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D sludge_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float fill_level : hint_range(0.0, 1.0) = 0.0;
uniform bool highlighted = false;
uniform bool targeting = false;
uniform bool available = true;
uniform bool rooted_frame = false;

const float GLASS_RADIUS = 0.853;

float liquid_surface(float x, float level, float time) {
	float side = x / GLASS_RADIUS;
	float strength = (0.54 + 0.46 * sin(level * PI)) * smoothstep(0.0, 0.13, level);
	float shoulder = -0.071 * pow(abs(side), 3.5);
	float swell = 0.046 * sin(side * 3.65 + time * 1.22) + 0.018 * sin(side * 7.4 - time * 1.57);
	float offset = side - 0.41 * sin(time * 0.71 + 0.23);
	float heave = 0.5 + 0.5 * sin(time * 1.51);
	float dome = -0.068 * exp(-44.0 * offset * offset) * heave * heave;
	return GLASS_RADIUS * (1.052 - 2.13 * level + strength * (shoulder + swell + dome));
}

vec3 draw_bubbles(vec3 liquid, vec2 point, float level, float time) {
	for (int index = 0; index < 9; index++) {
		float seed = (float(index) + 1.0) * 0.618034;
		float phase = fract(time / (3.3 + mod(float(index), 4.0) * 0.72) + seed);
		float side = fract(seed) * 1.67 - 0.835 + 0.052 * sin(phase * 4.4 + seed * 19.0);
		float x = side * GLASS_RADIUS;
		float rim_depth = GLASS_RADIUS * sqrt(1.0 - side * side);
		float floor_y = rim_depth * 0.965;
		float ceiling_y = max(-rim_depth * 0.96, liquid_surface(x, level, time));
		float column = floor_y - ceiling_y;
		float size = min(GLASS_RADIUS * (0.029 + fract(seed * 2.62) * 0.045), max(column, 0.001) * 0.174);
		float life = smoothstep(0.0, 0.28, phase) * (1.0 - smoothstep(0.76, 1.0, phase));
		life *= smoothstep(0.085, 0.15, column);
		float squash = smoothstep(0.57, 0.97, phase);
		float y = mix(floor_y - size * 0.73, ceiling_y + size * 0.63, smoothstep(0.0, 1.0, phase));
		vec2 shape = vec2(mix(0.86, 1.23, squash), mix(0.93, 0.66, squash));
		vec2 bubble = (point - vec2(x, y)) / (shape * max(size, 0.012));
		float silhouette = 1.0 - smoothstep(0.70, 1.0, length(bubble));
		float sheen = 1.0 - smoothstep(0.12, 0.67, length(bubble + vec2(0.30, 0.43)));
		vec3 dome = mix(vec3(0.15, 0.15, 0.057), vec3(0.58, 0.51, 0.26), sheen);
		liquid = mix(liquid, dome, silhouette * life * 0.55);
	}
	return liquid;
}

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radius = length(point);
	float edge = max(fwidth(radius), 0.008);
	vec4 art = texture(TEXTURE, UV);
	float glass = 1.0 - smoothstep(GLASS_RADIUS - edge, GLASS_RADIUS + edge, radius);
	// The atlas alpha stores opacity of roots, bone, crust and glass highlights.
	float transmission = glass * (1.0 - art.a);
	float time = TIME;
	vec3 color = art.rgb;
	float pulse = 0.5 + 0.5 * sin(time * 1.75);
	float haze = 1.0 - smoothstep(0.07, 0.72, length(point - vec2(0.10 * sin(time * 0.72), 0.15)));
	color += vec3(0.17, 0.19, 0.066) * transmission * haze * mix(0.09, 0.34, pulse);

	if (fill_level > 0.001 && transmission > 0.003) {
		float surface = liquid_surface(point.x, fill_level, time);
		float depth = (point.y - surface) / GLASS_RADIUS;
		float coverage = smoothstep(-0.012, 0.025, depth);
		float drift = sin(time * 0.56);
		vec2 flow = vec2(0.075 * drift - point.y * 0.049 * sin(time * 0.58),
			0.072 * sin(time * 0.70) + 0.18 * (1.0 - fill_level));
		vec3 liquid = texture(sludge_texture, vec2(0.5) + (point - flow) * vec2(0.45, 0.40)).rgb;
		liquid *= mix(1.06, 0.56, smoothstep(0.09, 1.82, depth));
		float fold_width = 0.096 * (0.82 + 0.25 * cos(point.x / GLASS_RADIUS * 5.0 - time));
		float fold = smoothstep(0.0, 0.022, depth) * (1.0 - smoothstep(0.028, fold_width, depth));
		float highlight = 0.5 + 0.5 * cos(point.x * 7.0 + time * 0.62);
		liquid += vec3(0.22, 0.20, 0.10) * (fold * mix(0.15, 0.57, highlight) + haze * 0.23 * pulse);
		liquid = draw_bubbles(liquid, point, fill_level, time);
		color = mix(color, liquid, coverage * transmission * 0.93);
	}

	if ((highlighted || targeting) && available) {
		float strength = targeting ? 0.25 : 0.10;
		float rim = smoothstep(0.80, 0.90, radius);
		if (targeting && rooted_frame) {
			// The roots cover the outer glass edge, so bring the targeting glow inward.
			strength = 0.45;
			rim = smoothstep(0.72, 0.86, radius);
		}
		color += vec3(0.46, 0.52, 0.23) * strength * rim;
	}
	if (!available) {
		color *= mix(0.65, 0.90, transmission);
	}
	float circle = 1.0 - smoothstep(0.92 - edge, 0.92 + edge, radius);
	float shadow_radius = length(point - vec2(0.0, 0.060));
	float shadow = (1.0 - smoothstep(0.83, 0.99, shadow_radius)) * 0.63;
	COLOR = vec4(color * circle, mix(shadow, 1.0, circle));
}
