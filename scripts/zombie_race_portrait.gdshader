shader_type canvas_item;

uniform vec2 rest_offset;
uniform vec2 ground_height;
uniform float haze = 0.0;
varying vec4 portrait_tint;

void vertex() {
	portrait_tint = COLOR;
}

void fragment() {
	float height = (ground_height.x - UV.y) / ground_height.y;
	vec4 pose = texture(TEXTURE, UV);
	vec4 rest = texture(TEXTURE, UV + rest_offset);
	// Hold the registered boots from the rest drawing while the upper body changes frames.
	float planted = 1.0 - smoothstep(0.19, 0.30, height);
	float alpha = mix(pose.a, rest.a, planted);
	vec3 painted = mix(pose.rgb * pose.a, rest.rgb * rest.a, planted) / max(alpha, 0.001);
	painted *= mix(vec3(0.83, 0.81, 0.83), vec3(1.0), smoothstep(0.0, 0.28, height));
	COLOR = vec4(mix(painted * portrait_tint.rgb, vec3(0.32, 0.26, 0.28), haze), alpha * portrait_tint.a);
}
