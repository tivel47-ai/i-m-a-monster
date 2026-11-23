shader_type canvas_item;

#include "res://assets/sprites/buildings/door_swing.gdshaderinc"

instance uniform float opening = 0.0;
instance uniform bool intact = true;
uniform vec4 atlas_rect;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 point = (UV / TEXTURE_PIXEL_SIZE - atlas_rect.xy) / atlas_rect.zw;
	vec3 leaf = door_leaf_sample(point, opening);
	vec2 wood_uv = (atlas_rect.xy + leaf.xy * atlas_rect.zw) * TEXTURE_PIXEL_SIZE;
	vec3 wood = texture(TEXTURE, wood_uv).rgb;
	float floor_depth = smoothstep(0.77, 1.0, point.y);
	vec3 recess = mix(vec3(0.065, 0.051, 0.036), vec3(0.24, 0.19, 0.14), floor_depth);
	COLOR = vec4(mix(recess, wood, intact ? leaf.z : 0.0), 1.0) * tint;
}
