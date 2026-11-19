shader_type canvas_item;
render_mode unshaded;

uniform sampler2D surface_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 tile_size = vec2(200.0);
uniform int surface_kind;
uniform vec2 pattern_axis = vec2(1.0, 0.0);
uniform vec2 pattern_origin;
uniform float motion_time;
uniform sampler2D edge_map : filter_linear, repeat_disable;
uniform vec2 edge_origin;
uniform vec2 edge_size = vec2(1.0);
uniform float edge_texel_size;

varying vec2 world_position;
varying vec2 terrain_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	terrain_position = VERTEX;
}

float hash_value(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise_at(vec2 point) {
	vec2 cell = floor(point);
	vec2 part = fract(point);
	part = part * part * (3.0 - 2.0 * part);
	return mix(
		mix(hash_value(cell), hash_value(cell + vec2(1.0, 0.0)), part.x),
		mix(hash_value(cell + vec2(0.0, 1.0)), hash_value(cell + 1.0), part.x),
		part.y
	);
}

vec3 sample_surface(vec2 uv) {
	// Blend across the tile borders while retaining the original detail away from them.
	vec2 edge = min(fract(uv), 1.0 - fract(uv));
	float center_weight = smoothstep(0.0, 0.14, min(edge.x, edge.y));
	return mix(texture(surface_texture, uv + vec2(0.46, 0.57)).rgb,
		texture(surface_texture, uv).rgb, center_weight);
}

float terrain_distance() {
	vec2 uv = (terrain_position - edge_origin) / edge_size;
	return (texture(edge_map, uv).r * 255.0 - 128.0) * (edge_texel_size / 4.0);
}

void fragment() {
	vec2 world = world_position;
	vec2 uv = world / tile_size;
	if (surface_kind == 6) {
		uv = world.yx / tile_size;
	}
	vec3 albedo;
	float opacity = COLOR.a;
	float distance_to_edge = 0.0;
	if (surface_kind == 1 || surface_kind == 3 || surface_kind == 5 || surface_kind == 7) {
		distance_to_edge = terrain_distance();
		if (distance_to_edge <= -5.0) {
			discard;
		}
		if (distance_to_edge < 5.0) {
			// Vary how softly surfaces meet, keeping half coverage on the authored edge.
			float softness = noise_at(world / 145.0 + vec2(3.5, 8.9));
			float spread = mix(2.8, 4.8, softness);
			if (surface_kind == 3) {
				spread = mix(2.1, 3.0, softness);
			}
			opacity *= smoothstep(-spread, spread, distance_to_edge);
		}
	}
	if (surface_kind == 3) {
		// Move the ripples downstream beneath the fixed shoreline.
		uv.x += sin(world.y * 0.028 - motion_time * 0.8) * 0.045;
		uv.y -= motion_time * 0.072;
		albedo = sample_surface(uv);
		float ripples = noise_at(vec2(world.x * 0.036, (world.y - motion_time * 22.0) * 0.16));
		albedo += smoothstep(0.71, 0.97, ripples) * vec3(0.07, 0.11, 0.12);
		float shelf = noise_at(world / 62.0);
		float deep = smoothstep(0.0, 8.0 + 10.0 * shelf, distance_to_edge);
		vec3 shallows = albedo * vec3(1.14, 1.21, 1.16) + vec3(0.033, 0.044, 0.031) * shelf;
		albedo = mix(shallows, albedo, deep);
	} else {
		albedo = sample_surface(uv);
		float mottling = noise_at(world / 92.0) * 0.7 + noise_at(world / 29.0) * 0.3;
		if (surface_kind == 0) {
			albedo *= mix(vec3(0.79, 0.85, 0.91), vec3(1.28, 1.25, 1.18), mottling);
		} else if (surface_kind == 1) {
			albedo *= mix(1.06, 1.38, mottling);
		} else if (surface_kind == 2) {
			float cross_row = dot(world - pattern_origin, pattern_axis);
			float row = fract((cross_row + (mottling - 0.5) * 2.3) / 14.0);
			float ridge = smoothstep(0.13, 0.44, row) * (1.0 - smoothstep(0.61, 0.91, row));
			albedo *= mix(vec3(0.54, 0.52, 0.49), vec3(1.07, 0.98, 0.89), ridge);
		} else if (surface_kind == 4) {
			float width_along = (world.x - pattern_origin.x) / 12.0;
			float plank = fract(width_along);
			float seam = smoothstep(0.015, 0.09, min(plank, 1.0 - plank));
			float tint = hash_value(vec2(floor(width_along), 0.0));
			albedo *= mix(0.42, 1.08 + tint * 0.30, seam);
			float peg = length(vec2((plank - 0.5) * 12.0, abs(world.y - pattern_origin.y) - 51.0));
			albedo *= mix(0.59, 1.0, smoothstep(0.65, 1.3, peg));
		} else if (surface_kind == 6) {
			albedo *= 1.32;
		} else if (surface_kind == 7) {
			albedo *= mix(0.84, 1.05, mottling);
			opacity *= mix(0.0, 0.33, noise_at(world / 12.0));
		} else if (surface_kind == 5) {
			float wet = smoothstep(4.0, 13.0, distance_to_edge);
			vec3 silt = mix(vec3(0.90, 0.91, 0.87), vec3(1.16, 1.13, 1.04), mottling);
			albedo *= mix(silt, vec3(0.59, 0.72, 0.76), wet);
		}
	}
	COLOR = vec4(albedo, opacity);
}
