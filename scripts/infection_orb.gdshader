shader_type canvas_item;
render_mode unshaded;

uniform float fill_level : hint_range(0.0, 1.0) = 0.0;
uniform bool highlighted = false;
uniform bool targeting = false;
uniform bool available = true;

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radius = length(point);
	float edge = max(fwidth(radius), 0.01);
	float circle = 1.0 - smoothstep(0.92 - edge, 0.92 + edge, radius);
	float shadow_radius = length(point - vec2(0.0, 0.06));
	float shadow = (1.0 - smoothstep(0.84, 0.99, shadow_radius)) * 0.64;

	// Directional bevel and fine grooves in the dark green metal.
	float angle = atan(point.y, point.x);
	float light = 0.5 + 0.5 * cos(angle + 2.0);
	float grain = 0.93 + 0.07 * cos(61.0 * angle + 1.7 * sin(27.0 * angle));
	vec3 frame = mix(vec3(0.13, 0.20, 0.13), vec3(0.48, 0.60, 0.34), light) * grain;
	frame *= 1.0 - 0.76 * smoothstep(0.856, 0.875, radius);
	frame *= mix(0.36, 1.0, smoothstep(0.786, 0.817, radius));
	frame += vec3(0.19, 0.25, 0.12) * (1.0 - smoothstep(0.009, 0.033, abs(radius - 0.844))) * light;

	float glass_radius = 0.755;
	float glass_mask = 1.0 - smoothstep(glass_radius - edge, glass_radius + edge, radius);
	float side = point.x / glass_radius;
	float curve = 0.056 * (1.0 - side * side);
	float surface = mix(glass_radius, -glass_radius, fill_level) + curve;
	float liquid = smoothstep(surface - edge, surface + edge, point.y);
	liquid *= step(0.001, fill_level);
	float depth = clamp((point.y - surface) / glass_radius, 0.0, 1.0);
	float body_light = 1.0 - smoothstep(0.04, 0.87, length(point - vec2(-0.22, 0.17)));
	vec3 water = mix(vec3(0.06, 0.27, 0.07), vec3(0.47, 0.85, 0.20), body_light);
	water *= mix(1.0, 0.69, depth);
	float meniscus = (1.0 - smoothstep(0.002, 0.034, abs(point.y - surface))) * step(0.001, fill_level);
	float glass_light = 1.0 - smoothstep(0.0, 0.85, length(point - vec2(-0.20, -0.26)));
	vec3 glass = mix(vec3(0.027, 0.053, 0.038), vec3(0.17, 0.25, 0.16), glass_light);
	glass = mix(glass, water, liquid) + vec3(0.47, 0.73, 0.29) * meniscus * 0.60;
	glass *= 1.0 - 0.53 * smoothstep(0.50, glass_radius, radius);
	float reflection = length((point - vec2(0.28, -0.36)) * vec2(0.94, 1.19));
	glass += vec3(0.62, 0.80, 0.53) * (0.51 * exp(-88.0 * reflection * reflection) + 0.16 * exp(-14.0 * reflection * reflection));

	if ((highlighted || targeting) && available) {
		float intensity = targeting ? 1.0 : 0.30;
		frame += vec3(0.33, 0.49, 0.16) * smoothstep(0.79, 0.85, radius) * intensity;
	}
	if (!available) {
		frame *= 0.65;
	}
	vec3 color = mix(frame, glass, glass_mask);
	float alpha = mix(shadow, 1.0, circle);
	COLOR = vec4(color * circle / max(alpha, 0.001), alpha);
}
