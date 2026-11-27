shader_type canvas_item;
render_mode unshaded;

uniform vec2 art_center_uv;
uniform float art_scale;
uniform float max_rank = 5.0;
uniform float rank = 0.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 local = (UV - art_center_uv) * art_scale;
	float radius = length(local);
	vec4 art = texture(TEXTURE, UV);
	// Preserve the clear interior and exclude faint stray pixels from the cutout.
	if (rank <= 0.0 || radius < 0.526 || radius > 0.735 || art.a < 4.0 / 255.0) {
		discard;
	}

	// Screen Y grows down, so this sweeps from the left through the lower half.
	float along = fract((PI - atan(local.y, local.x)) / TAU);
	float tier_position = along * max_rank;
	float from_tier = abs(tier_position - round(tier_position));
	float knot = exp(-pow(from_tier * 20.0, 2.0));
	float progress = rank / max_rank;
	float strays = min(1.0, abs(radius - 0.612) / 0.064);
	float tip_width = 0.012 + strays * 0.008 + 0.0025 * sin(radius * 144.37);
	float fill = progress >= 1.0 ? 1.0 : smoothstep(0.0, tip_width, progress - along - strays * 0.004);

	COLOR = vec4(art.rgb * (1.0 + knot * 0.10), art.a * fill) * tint;
}
