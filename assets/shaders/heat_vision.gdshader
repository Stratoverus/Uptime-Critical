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
uniform float airflow_overlay_visual_gain = 1.0;
uniform float airflow_line_scale = 64.0;
uniform float airflow_scroll_speed = 1.1;
uniform float airflow_visual_min_scroll_speed = 0.45;
uniform float airflow_visual_max_scroll_speed = 1.2;
uniform float airflow_visual_speed_curve = 0.7;
uniform float airflow_streamline_density = 2.1;
uniform float airflow_streamline_thickness = 0.22;
uniform float airflow_streamline_jitter = 0.33;
uniform int airflow_streamline_samples = 6;
uniform float airflow_streamline_span_cells = 1.35;
uniform float airflow_streamline_dash_repeat = 3.4;
uniform float airflow_streamline_dash_duty = 0.36;
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

vec2 decode_flow(vec3 flow_sample) {
	return (flow_sample.rg * 2.0) - vec2(1.0);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float streamline_signal(vec2 heat_uv, vec2 world_pos, vec2 flow_dir, float flow_magnitude, float visual_scroll_speed) {
	vec3 local_flow = sample_airflow(heat_uv);
	if (local_flow.b <= 0.001) {
		return 0.0;
	}

	vec2 grid = world_pos - simulation_origin;
	vec2 cell = grid * (heat_grid_size / max(simulation_size, vec2(0.001)));
	float density = max(airflow_streamline_density, 0.2);
	float lane_spacing_cells = max((airflow_line_scale * 0.1) / density, 0.9);
	float dash_duty = clamp(airflow_streamline_dash_duty, 0.08, 0.92);
	float dash_repeat = max(airflow_streamline_dash_repeat, 0.5);
	float thickness = clamp(airflow_streamline_thickness, 0.02, 0.95);
	vec2 n = vec2(-flow_dir.y, flow_dir.x);
	float lane_coord = dot(cell, n) / lane_spacing_cells;
	float lane_phase = abs(fract(lane_coord + (hash12(floor(cell * 0.35)) - 0.5) * airflow_streamline_jitter) - 0.5);
	float half_width = thickness * 0.08;
	float lane_mask = 1.0 - smoothstep(half_width, half_width + 0.018, lane_phase);

	float along_coord = (dot(cell, flow_dir) / lane_spacing_cells) * dash_repeat;
	float phase = fract(along_coord - (TIME * visual_scroll_speed));
	float edge = 0.06;
	float dash_mask = smoothstep(0.0, edge, phase) * (1.0 - smoothstep(dash_duty, min(dash_duty + edge, 1.0), phase));

	float upstream = 0.0;
	float weight = 0.0;
	for (int i = 0; i < 5; i++) {
		float t = float(i) / 4.0;
		float w = 1.0 - t;
		vec2 uv = heat_uv - (flow_dir * heat_texel_size * airflow_streamline_span_cells * (t * 4.0));
		vec3 s = sample_airflow(uv);
		upstream += clamp(s.b * airflow_overlay_visual_gain, 0.0, 1.0) * w;
		weight += w;
	}
	float upstream_mag = upstream / max(weight, 0.001);
	return lane_mask * dash_mask * upstream_mag;
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

		float hot = sample_hot(heat_uv);
		float cold = sample_cold(heat_uv);
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
			vec2 flow = decode_flow(flow_sample);
			float flow_magnitude = clamp(flow_sample.b, 0.0, 1.0);

			if (flow_magnitude > 0.0015) {
				vec2 flow_dir_raw = normalize(flow + vec2(0.0001));
				vec2 flow_dir = normalize(flow_dir_raw + vec2(0.0001));
				vec2 dir_x = normalize(decode_flow(flow_x) + vec2(0.0001));
				vec2 dir_xn = normalize(decode_flow(flow_xn) + vec2(0.0001));
				vec2 dir_y = normalize(decode_flow(flow_y) + vec2(0.0001));
				vec2 dir_yn = normalize(decode_flow(flow_yn) + vec2(0.0001));
				float coherence = 0.0;
				coherence += max(dot(flow_dir, dir_x), 0.0);
				coherence += max(dot(flow_dir, dir_xn), 0.0);
				coherence += max(dot(flow_dir, dir_y), 0.0);
				coherence += max(dot(flow_dir, dir_yn), 0.0);
				coherence *= 0.25;
				float coherence_mask = smoothstep(0.35, 0.85, coherence);
				float boosted_magnitude = clamp(flow_magnitude * airflow_overlay_visual_gain, 0.0, 1.0);
				float speed_t = pow(boosted_magnitude, max(airflow_visual_speed_curve, 0.01));
				float visual_scroll_speed = airflow_scroll_speed * mix(airflow_visual_min_scroll_speed, airflow_visual_max_scroll_speed, speed_t);
				float streak = streamline_signal(heat_uv, world_pos, flow_dir, boosted_magnitude, visual_scroll_speed);
				float hot_mask = clamp(hot * 1.2, 0.0, 1.0);
				float overlay_alpha = streak * coherence_mask * airflow_overlay_strength * inside * (1.0 - (hot_mask * 0.35));
				thermal_tint = mix(thermal_tint, vec3(0.8, 0.98, 1.0), overlay_alpha);
				final_alpha = min(0.9, final_alpha + (overlay_alpha * 0.58));
			}
		}

		COLOR = vec4(thermal_tint, clamp(final_alpha, 0.0, 0.85));
	}
}
