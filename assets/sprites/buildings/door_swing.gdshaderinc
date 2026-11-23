// Project each leaf inward around its outside hinge and clip it at the arch.
vec3 door_leaf_sample(vec2 point, float opening) {
	float angle = opening * 1.18;
	float hinge_distance = min(point.x, 1.0 - point.x) / cos(angle);
	float leaf_x = point.x < 0.5 ? hinge_distance : 1.0 - hinge_distance;
	vec2 leaf_uv = vec2(leaf_x, point.y + 0.26 * hinge_distance * sin(angle));
	float coverage = step(hinge_distance, 0.5) * step(leaf_uv.y, 1.0);
	return vec3(leaf_uv, coverage);
}
