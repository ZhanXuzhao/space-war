shader_type spatial;
render_mode blend_add, unshaded, shadows_disabled, cull_disabled;

uniform vec4 center_color : source_color = vec4(1.0, 0.6, 0.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.1, 0.05, 1.0);
uniform float emission_strength : hint_range(0.0, 20.0) = 8.0;
uniform float edge_fade_power : hint_range(0.5, 6.0) = 2.5;

void fragment() {
	// 纯光线效果：法线与视线方向点积 → 中心亮边缘暗
	float center = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float intensity = pow(center, edge_fade_power);
	
	// 中间橙色 → 边缘红色 渐变
	vec3 color = mix(edge_color.rgb, center_color.rgb, intensity);
	
	ALBEDO = color * intensity;
	EMISSION = color * intensity * emission_strength;
	ALPHA = intensity * 0.85;
}
