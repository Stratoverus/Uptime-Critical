shader_type canvas_item;
render_mode unshaded;

uniform bool heat_view_enabled = false;
uniform sampler2D heat_texture : source_color, repeat_disable, filter_linear;
uniform vec2 heat_texel_size = vec2(0.004166667, 0.007407407);
uniform vec2 viewport_size = vec2(1920.0, 1080.0);
uniform vec2 view_world_top_left = vec2(0.0, 0.0);
uniform vec2 simulation_origin = vec2(0.0, 0.0);
uniform vec2 simulation_size = vec2(1920.0, 1280.0);
uniform float neutral_alpha = 0.08;
uniform float hot_alpha = 0.42;
uniform float cold_alpha = 0.35;

float sample_hot(vec2 uv) {
	return clamp(texture(heat_texture, uv).r, 0.0, 1.0);
}

float sample_cold(vec2 uv) {
	return clamp(texture(heat_texture, uv).g, 0.0, 1.0);
}

void fragment() {
	if (!heat_view_enabled) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		vec2 world_pos = view_world_top_left + (SCREEN_UV * viewport_size);
		vec2 heat_uv = (world_pos - simulation_origin) / max(simulation_size, vec2(0.001));
		float inside = step(0.0, heat_uv.x) * step(0.0, heat_uv.y) * step(heat_uv.x, 1.0) * step(heat_uv.y, 1.0);

		float hot = sample_hot(heat_uv) * 0.4;
		hot += sample_hot(heat_uv + vec2(heat_texel_size.x, 0.0)) * 0.15;
		hot += sample_hot(heat_uv - vec2(heat_texel_size.x, 0.0)) * 0.15;
		hot += sample_hot(heat_uv + vec2(0.0, heat_texel_size.y)) * 0.15;
		hot += sample_hot(heat_uv - vec2(0.0, heat_texel_size.y)) * 0.15;

		float cold = sample_cold(heat_uv) * 0.4;
		cold += sample_cold(heat_uv + vec2(heat_texel_size.x, 0.0)) * 0.15;
		cold += sample_cold(heat_uv - vec2(heat_texel_size.x, 0.0)) * 0.15;
		cold += sample_cold(heat_uv + vec2(0.0, heat_texel_size.y)) * 0.15;
		cold += sample_cold(heat_uv - vec2(0.0, heat_texel_size.y)) * 0.15;

		hot *= inside;
		cold *= inside;

		hot = pow(clamp(hot, 0.0, 1.0), 0.6);
		cold = pow(clamp(cold, 0.0, 1.0), 0.6);

		float normalized_temperature = clamp(hot - cold, -1.0, 1.0);
		float temperature_strength = abs(normalized_temperature);
		vec3 thermal_tint = vec3(1.0);
		if (normalized_temperature > 0.0) {
			thermal_tint = mix(vec3(1.0), vec3(1.0, 0.0, 0.0), normalized_temperature);
		} else if (normalized_temperature < 0.0) {
			thermal_tint = mix(vec3(1.0), vec3(0.2, 0.5, 1.0), -normalized_temperature);
		}

		float extra_alpha = hot_alpha;
		if (normalized_temperature < 0.0) {
			extra_alpha = cold_alpha;
		}

		float final_alpha = neutral_alpha + (extra_alpha * temperature_strength);
		COLOR = vec4(thermal_tint, clamp(final_alpha, 0.0, 0.85));
	}
}
