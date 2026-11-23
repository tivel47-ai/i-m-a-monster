shader_type canvas_item;

#include "res://assets/sprites/buildings/door_swing.gdshaderinc"

instance uniform float opening = 1.0;
instance uniform bool intact = true;
instance uniform float light_time = 0.0;

const float SPILL_PIXELS = 30.0;
const vec3 SUNLIGHT = vec3(1.0, 0.88, 0.65);
varying vec4 tint;

float ray(vec2 point, vec2 origin, float slope, float width) {
	float distance_down = max(point.y - origin.y, 0.0);
	float distance_from_ray = abs(point.x - origin.x - slope * distance_down);
	float spread = width + 0.018 * distance_down;
	float shimmer = 0.83 + 0.12 * sin(light_time * 1.6 + origin.x * 11.0);
	return (1.0 - smoothstep(spread * 0.28, spread, distance_from_ray)) *
		smoothstep(0.02, 0.25, distance_down) * shimmer;
}

float dust(vec2 point, vec2 texel) {
	float result = 0.0;
	for (int i = 0; i < 8; i++) {
		float seed = float(i);
		float phase = fract(light_time * (0.20 + 0.018 * seed) + 0.618 * seed);
		float direction = fract(0.7549 * seed + 0.17) - 0.5;
		vec2 center = vec2(
			0.50 + direction * mix(0.32, 0.74, phase) + 0.023 * sin(2.2 * light_time + seed),
			mix(0.27, 1.34, phase)
		);
		vec2 offset = abs(point - center) / texel;
		float size = 1.55 + 0.8 * fract(0.49 * seed);
		float core = 1.0 - smoothstep(0.25, size, length(offset));
		float glint = (1.0 - smoothstep(0.28, 1.10, min(offset.x, offset.y))) *
			(1.0 - smoothstep(size, size + 1.45, max(offset.x, offset.y)));
		float twinkle = 0.36 + 0.64 * pow(0.5 + 0.5 * sin(4.8 * light_time + 2.0 * seed), 2.0);
		float life = smoothstep(0.0, 0.16, phase) * (1.0 - smoothstep(0.76, 1.0, phase));
		result = max(result, max(core, glint * 0.65) * twinkle * life);
	}
	return result;
}

void vertex() {
	tint = COLOR;
	// Extend the sprite onto the threshold while keeping the door texture at its original scale.
	VERTEX.y += UV.y * SPILL_PIXELS;
}

void fragment() {
	float spill_height = SPILL_PIXELS * TEXTURE_PIXEL_SIZE.y;
	vec2 point = vec2(UV.x, UV.y * (1.0 + spill_height));
	if (intact && opening <= 0.0) {
		COLOR = point.y <= 1.0 ? texture(TEXTURE, point) * tint : vec4(0.0);
	} else {
		float rays = ray(point, vec2(0.22, 0.37), -0.085, 0.029) +
			ray(point, vec2(0.33, 0.26), -0.062, 0.038) +
			ray(point, vec2(0.44, 0.32), -0.025, 0.028) +
			ray(point, vec2(0.55, 0.23), 0.022, 0.043) +
			ray(point, vec2(0.66, 0.30), 0.054, 0.031) +
			ray(point, vec2(0.78, 0.36), 0.090, 0.029);
		float motes = dust(point, TEXTURE_PIXEL_SIZE);
		if (point.y <= 1.0) {
			vec4 arch = texture(TEXTURE, point);
			vec3 leaf = door_leaf_sample(point, opening);
			vec4 wood = texture(TEXTURE, leaf.xy);
			float coverage = intact ? leaf.z * wood.a : 0.0;
			float center_distance = length((point - vec2(0.49, 0.43)) * vec2(1.50, 0.88));
			float falloff = 1.0 - smoothstep(0.05, 0.67, center_distance);
			vec3 recess = mix(vec3(0.19, 0.15, 0.11), vec3(0.65, 0.53, 0.35), falloff);
			float glow = clamp(0.38 * falloff * falloff + 0.34 * rays + 0.86 * motes, 0.0, 1.0);
			COLOR = vec4(mix(mix(recess, SUNLIGHT, glow), wood.rgb, coverage), arch.a) * tint;
		} else {
			float outward = (point.y - 1.0) / spill_height;
			float edge = smoothstep(0.0, 0.18, point.x) * (1.0 - smoothstep(0.82, 1.0, point.x));
			float fade = edge * (1.0 - smoothstep(0.0, 1.0, outward));
			float visible_light = intact ? smoothstep(0.10, 0.92, opening) : 1.0;
			float opacity = min(0.11 + 0.36 * rays + 0.72 * motes, 1.0) * fade * visible_light;
			COLOR = vec4(SUNLIGHT, opacity) * tint;
		}
	}
}
