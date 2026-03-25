shader_type canvas_item;
render_mode unshaded;

uniform bool heat_view_enabled = false;
uniform bool thermal_signal_present = true;
uniform sampler2D heat_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D airflow_texture : source_color, repeat_disable, filter_linear;
uniform sampler2D airflow_texture_prev : source_color, repeat_disable, filter_linear;
uniform float airflow_texture_blend = 1.0;
uniform vec2 heat_texel_size = vec2(0.004166667, 0.007407407);
uniform vec2 heat_grid_size = vec2(100.0, 56.0);
uniform vec2 viewport_size = vec2(1920.0, 1080.0);
uniform vec2 view_world_top_left = vec2(0.0, 0.0);
uniform vec2 simulation_origin = vec2(0.0, 0.0);
uniform vec2 simulation_size = vec2(1920.0, 1280.0);
uniform bool airflow_overlay_enabled = true;
uniform float airflow_overlay_strength = 0.35;
uniform float airflow_line_scale = 64.0;
uniform float airflow_scroll_speed = 1.1;
uniform float airflow_visual_min_scroll_speed = 0.45;
uniform float airflow_visual_max_scroll_speed = 1.2;
uniform float airflow_visual_speed_curve = 0.7;
uniform float neutral_alpha = 0.08;
uniform float hot_alpha = 0.54;
uniform float cold_alpha = 0.35;

float sample_hot(vec2 uv) {
	return clamp(texture(heat_texture, uv).r, 0.0, 1.0);
}

float sample_cold(vec2 uv) {
	return clamp(texture(heat_texture, uv).g, 0.0, 1.0);
}

vec3 sample_airflow(vec2 uv) {
	vec3 flow_prev = texture(airflow_texture_prev, uv).rgb;
	vec3 flow_curr = texture(airflow_texture, uv).rgb;
	return mix(flow_prev, flow_curr, clamp(airflow_texture_blend, 0.0, 1.0));
}

void fragment() {
	if (!heat_view_enabled) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else if (!thermal_signal_present) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		vec2 world_pos = view_world_top_left + (SCREEN_UV * viewport_size);
		vec2 heat_uv = (world_pos - simulation_origin) / max(simulation_size, vec2(0.001));
		float inside = step(0.0, heat_uv.x) * step(0.0, heat_uv.y) * step(heat_uv.x, 1.0) * step(heat_uv.y, 1.0);

		float hot = sample_hot(heat_uv) * 0.55;
		float cold = sample_cold(heat_uv) * 0.4;
		hot += sample_hot(heat_uv + vec2(heat_texel_size.x, 0.0)) * 0.2;
		hot += sample_hot(heat_uv + vec2(0.0, heat_texel_size.y)) * 0.2;
		cold += sample_cold(heat_uv + vec2(heat_texel_size.x, 0.0)) * 0.2;
		cold += sample_cold(heat_uv + vec2(0.0, heat_texel_size.y)) * 0.2;
		hot *= inside;
		cold *= inside;

		hot = pow(clamp(hot, 0.0, 1.0), 0.5);
		cold = pow(clamp(cold, 0.0, 1.0), 0.6);

		float normalized_temperature = clamp(hot - cold, -1.0, 1.0);
		float temperature_strength = abs(normalized_temperature);
		vec3 thermal_tint = vec3(1.0);
		if (normalized_temperature > 0.0) {
			float hot_t = pow(clamp(normalized_temperature, 0.0, 1.0), 0.75);
			thermal_tint = mix(vec3(1.0), vec3(1.0, 0.02, 0.0), hot_t);
		} else if (normalized_temperature < 0.0) {
			thermal_tint = mix(vec3(1.0), vec3(0.2, 0.5, 1.0), -normalized_temperature);
		}

		float extra_alpha = hot_alpha * 1.2;
		if (normalized_temperature < 0.0) {
			extra_alpha = cold_alpha;
		}

		float final_alpha = neutral_alpha + (extra_alpha * temperature_strength);

		if (airflow_overlay_enabled) {
			vec3 flow_center = sample_airflow(heat_uv);
			vec3 flow_x = sample_airflow(heat_uv + vec2(heat_texel_size.x, 0.0));
			vec3 flow_xn = sample_airflow(heat_uv - vec2(heat_texel_size.x, 0.0));
			vec3 flow_y = sample_airflow(heat_uv + vec2(0.0, heat_texel_size.y));
			vec3 flow_yn = sample_airflow(heat_uv - vec2(0.0, heat_texel_size.y));
			vec3 flow_sample = (flow_center * 0.4) + (flow_x * 0.15) + (flow_xn * 0.15) + (flow_y * 0.15) + (flow_yn * 0.15);
			vec2 flow = (flow_sample.rg * 2.0) - vec2(1.0);
			float flow_magnitude = clamp(flow_sample.b, 0.0, 1.0);

			if (flow_magnitude > 0.02) {
				vec2 flow_dir_raw = normalize(flow + vec2(0.0001));
				vec2 flow_dir = normalize(flow_dir_raw + vec2(0.0001));
				vec2 heat_cell = (world_pos - simulation_origin) * (heat_grid_size / max(simulation_size, vec2(0.001)));
				float speed_t = pow(clamp(flow_magnitude, 0.0, 1.0), max(airflow_visual_speed_curve, 0.01));
				float visual_scroll_speed = airflow_scroll_speed * mix(airflow_visual_min_scroll_speed, airflow_visual_max_scroll_speed, speed_t);
				float phase = fract(dot(heat_cell / max(airflow_line_scale, 0.001), flow_dir) - (TIME * visual_scroll_speed));
				float ridge = 1.0 - abs((phase * 2.0) - 1.0);
				float streak = pow(clamp(ridge, 0.0, 1.0), 3.1);
				float hot_mask = clamp(hot * 1.2, 0.0, 1.0);
				float overlay_alpha = streak * flow_magnitude * airflow_overlay_strength * inside * (1.0 - (hot_mask * 0.55));
				thermal_tint = mix(thermal_tint, vec3(0.82, 1.0, 1.0), overlay_alpha);
				final_alpha = min(0.85, final_alpha + (overlay_alpha * 0.42));
			}
		}

		COLOR = vec4(thermal_tint, clamp(final_alpha, 0.0, 0.85));
	}
}
