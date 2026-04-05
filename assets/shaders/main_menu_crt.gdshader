shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(0.30, 1.00, 0.52, 1.0);
uniform float static_strength : hint_range(0.0, 0.35) = 0.08;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.28;
uniform float distortion_strength : hint_range(0.0, 0.03) = 0.008;
uniform float top_wobble_multiplier : hint_range(0.0, 1.0) = 0.2;
uniform float top_wobble_ramp_height : hint_range(0.05, 0.9) = 0.35;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.26;
uniform float flicker_strength : hint_range(0.0, 0.2) = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Slight horizontal warp per scanline to mimic old tube distortion.
	float wobble_blend = smoothstep(0.0, top_wobble_ramp_height, uv.y);
	float wobble_scale = mix(top_wobble_multiplier, 1.0, wobble_blend);
	float wave = sin((uv.y * 210.0) + (TIME * 12.0));
	uv.x += wave * distortion_strength * wobble_scale;

	vec4 base = texture(TEXTURE, uv);

	// Animated static/noise pattern.
	float grain = hash(vec2(floor(uv.x * 380.0 + TIME * 47.0), floor(uv.y * 260.0 + TIME * 23.0)));
	float noise = (grain - 0.5) * (2.0 * static_strength);

	// Horizontal scanlines.
	float scanline = sin((uv.y * 1200.0) + (TIME * 3.2));
	float scanline_mask = 1.0 - ((scanline * 0.5 + 0.5) * scanline_strength);

	// Gentle global flicker.
	float flicker = 1.0 - (sin(TIME * 16.0) * 0.5 + 0.5) * flicker_strength;

	// CRT-style vignette focused toward center.
	vec2 centered = uv - vec2(0.5);
	float vignette = 1.0 - dot(centered, centered) * vignette_strength;
	vignette = clamp(vignette, 0.0, 1.0);

	vec3 color = base.rgb;
	color += noise;
	color *= tint_color.rgb;
	color *= scanline_mask * flicker * vignette;

	COLOR = vec4(color, base.a);
}
