shader_type canvas_item;

uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;
uniform float edge_softness : hint_range(0.001, 0.25) = 0.04;
uniform vec4 frontier_color : source_color = vec4(0.12, 0.96, 1.00, 1.0);
uniform float frontier_width : hint_range(0.01, 0.25) = 0.07;
uniform float frontier_intensity : hint_range(0.0, 2.5) = 1.15;
uniform float distortion_strength : hint_range(0.0, 0.04) = 0.010;
uniform float glitch_strength : hint_range(0.0, 0.05) = 0.012;
uniform float chroma_shift : hint_range(0.0, 0.02) = 0.003;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.20;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float progress = clamp(reveal_progress, 0.0, 1.0);
	float threshold = mix(-edge_softness, 1.0, progress);

	float bottom_to_top = 1.0 - UV.y;
	float alpha_mask = 1.0 - smoothstep(threshold, threshold + edge_softness, bottom_to_top);

	float dist_to_frontier = abs(bottom_to_top - threshold);
	float frontier_mask = 1.0 - smoothstep(0.0, frontier_width, dist_to_frontier);

	vec2 uv = UV;
	float wave = sin((uv.y * 180.0) + (TIME * 12.0)) * 0.5;
	wave += sin((uv.y * 420.0) - (TIME * 17.0)) * 0.5;
	float noise = hash(vec2(floor(uv.y * 260.0), floor(TIME * 40.0)));
	float glitch = (noise - 0.5) * 2.0 * glitch_strength;
	uv.x += (wave * distortion_strength + glitch) * (0.35 + frontier_mask * 0.65);

	vec2 shift = vec2(chroma_shift * frontier_mask, 0.0);
	float r = texture(TEXTURE, uv + shift).r;
	float g = texture(TEXTURE, uv).g;
	float b = texture(TEXTURE, uv - shift).b;
	float a = texture(TEXTURE, uv).a;

	vec3 color = vec3(r, g, b);

	float scanline = sin((UV.y * 1200.0) + (TIME * 8.0)) * 0.5 + 0.5;
	float scanline_mul = 1.0 - (scanline * scanline_strength);
	color *= scanline_mul;

	float glow = frontier_mask * frontier_intensity * alpha_mask;
	color = mix(color, frontier_color.rgb, glow * 0.55);
	color += frontier_color.rgb * glow * 0.35;

	COLOR = vec4(color, a * alpha_mask);
}
