shader_type canvas_item;
render_mode unshaded;

uniform sampler2D old_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D spread_atlas : filter_nearest, repeat_disable;
uniform sampler2D meadow : source_color, filter_linear_mipmap, repeat_enable;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aging : hint_range(0.0, 1.0) = 0.0;
uniform float grass : hint_range(0.0, 1.0) = 0.0;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 fresh = texture(TEXTURE, UV);
	vec3 mask = texture(spread_atlas, UV).rgb;
	float arrival = dot(mask.rg, vec2(65280.0, 255.0)) / 65535.0;
	if (fresh.a == 0.0 || progress < arrival) {
		discard;
	}
	vec3 color = mix(fresh.rgb, texture(old_atlas, UV).rgb, smoothstep(0.0, 1.0, aging));
	float alpha = fresh.a;
	if (grass > 0.0) {
		vec2 uv = world_position / 222.0;
		// Leave parts of the actual underlying grass visible at the narrow contact edge.
		float light = texture(meadow, uv).g;
		float nearby = texture(meadow, uv + vec2(0.004, 0.002)).g;
		float blade = smoothstep(0.015, 0.10, light - nearby);
		float cover = blade * (1.0 - mask.b) * grass;
		alpha *= (1.0 - 0.13 * grass) * (1.0 - 0.82 * cover);
	}
	COLOR = vec4(color, alpha);
}
