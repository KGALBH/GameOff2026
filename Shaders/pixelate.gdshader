shader_type canvas_item;
// 全屏像素化滤镜：把整个画面按 pixel_size 分成大方块取色，再可选地减少颜色数量，得到复古像素风。

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// 一个“像素”占多少个真实屏幕像素，越大越粗糙。
uniform float pixel_size : hint_range(1.0, 32.0, 1.0) = 4.0;
// 是否减少颜色（色阶化），更有像素游戏的味道。
uniform bool quantize_colors = true;
// 每个颜色通道保留几档颜色。
uniform float color_levels : hint_range(2.0, 64.0, 1.0) = 16.0;

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	// 对齐到大像素格的中心取色
	vec2 cell = floor(SCREEN_UV * screen_size / pixel_size) + 0.5;
	vec2 uv = cell * pixel_size / screen_size;
	vec3 c = texture(screen_tex, uv).rgb;
	if (quantize_colors) {
		float steps = color_levels - 1.0;
		c = floor(c * steps + 0.5) / steps;
	}
	COLOR = vec4(c, 1.0);
}
