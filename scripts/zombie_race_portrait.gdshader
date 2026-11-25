shader_type canvas_item;

uniform vec2 mesh_origin;
uniform vec2 ground;
uniform vec2 hip;
uniform vec2 neck;
uniform float portrait_height;
uniform float haze = 0.0;
uniform float facing = 1.0;
// Rotation and breathing scales around the hip. The neck adds a local turn.
uniform vec3 torso_motion = vec3(0.0, 1.0, 1.0);
uniform vec2 head_motion = vec2(0.0);
varying float height_above_ground;

vec2 rotate_joint(vec2 point, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat2(vec2(c, s), vec2(-s, c)) * point;
}

void vertex() {
	vec2 rest = VERTEX + mesh_origin;
	vec2 head = rest - neck;
	// Follow the jawline and leave the shoulder on the torso.
	float head_weight = smoothstep(-18.0, 18.0, 0.60 * head.x - head.y);
	vec2 turned = rotate_joint(head, head_motion.x);
	turned.x = turned.x * (1.0 - 0.07 * head_motion.y) - 2.5 * head_motion.y;
	vec2 point = mix(rest, neck + turned, head_weight);

	// Fade the hip rotation through the thighs to keep the shins and boots planted.
	float torso_weight = 1.0 - smoothstep(hip.y - 10.0, ground.y - 115.0, rest.y);
	vec2 torso = (point - hip) * torso_motion.yz;
	point = mix(rest, hip + rotate_joint(torso, torso_motion.x), torso_weight);

	height_above_ground = (ground.y - rest.y) / portrait_height;
	VERTEX = (point - ground) * vec2(facing, 1.0);
}

void fragment() {
	vec3 painted = COLOR.rgb * mix(vec3(0.83, 0.81, 0.83), vec3(1.0),
		smoothstep(0.0, 0.28, height_above_ground));
	COLOR = vec4(mix(painted, vec3(0.32, 0.26, 0.28), haze), COLOR.a);
}
