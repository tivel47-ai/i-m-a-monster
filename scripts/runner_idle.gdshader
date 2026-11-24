shader_type canvas_item;

uniform vec2 idle_motion;
varying vec4 sprite_tint;
varying vec2 sprite_position;

void vertex() {
	sprite_tint = COLOR;
	sprite_position = VERTEX;
}

void fragment() {
	// Keep the boots fixed and the sample inside the current atlas cell.
	float upper_body = smoothstep(32.0, 70.0, -sprite_position.y);
	float margin = (1.0 - smoothstep(58.0, 64.0, abs(sprite_position.x)))
		* (1.0 - smoothstep(86.0, 92.0, -sprite_position.y));
	vec2 source = UV - idle_motion * TEXTURE_PIXEL_SIZE * upper_body * margin;
	COLOR = texture(TEXTURE, source) * sprite_tint;
}
