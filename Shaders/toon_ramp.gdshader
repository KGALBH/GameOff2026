// 两段式卡通着色：复刻 Blender 里「漫射 BSDF → Shader to RGB → 颜色渐变(常值) → 自发光」的效果。
// 受光强度超过 threshold 的地方显示 lit_color，其余地方显示 shadow_color，中间没有过渡。
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

// 受光面颜色（颜色渐变右边那一段）。
uniform vec4 lit_color : source_color = vec4(1.0, 0.25, 0.08, 1.0);
// 背光面颜色（颜色渐变左边那一段）。
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// 分界线：受光强度（0~1，含阴影）超过它就算受光。对应 Blender 颜色渐变里色标的位置。
uniform float threshold : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	ALBEDO = vec3(1.0);
	// 背光颜色直接作为底色发出来，不受光照影响
	EMISSION = shadow_color.rgb;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	// 受光的地方在背光颜色的基础上补到受光颜色
	DIFFUSE_LIGHT += (lit_color.rgb - shadow_color.rgb) * step(threshold, lit);
}
