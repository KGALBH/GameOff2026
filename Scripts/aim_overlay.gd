extends Control
## 画瞄准框（AimReticle 自动创建，不需要手动摆）：
## 淡色圆 = 瞄准框能移动的范围；方框 = 瞄准框（锁定时变红）；锁定目标上画一个小方括号和伤害倍率。

var reticle: AimReticle


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if reticle == null or reticle._plane == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(reticle._plane.global_position):
		return
	var plane_pos: Vector3 = reticle._plane.global_position
	# 圆形范围（在飞机深度上投影，半径换算成像素）
	var c: Vector2 = cam.unproject_position(plane_pos)
	var edge: Vector2 = cam.unproject_position(plane_pos + Vector3(reticle.circle_radius + reticle.box_half_size, 0, 0))
	draw_arc(c, c.distance_to(edge), 0.0, TAU, 48, reticle.color_circle, 1.5)

	var locked: bool = is_instance_valid(reticle.target)
	var col: Color = reticle.color_locked if locked else reticle.color_idle
	_draw_brackets(reticle.box_screen_rect(cam), col, 3.0)

	if locked:
		var tp: Vector2 = cam.unproject_position(reticle.target.global_position)
		var r: Rect2 = Rect2(tp - Vector2(14, 14), Vector2(28, 28))
		_draw_brackets(r, reticle.color_locked, 2.0)
		var font: Font = get_theme_default_font()
		draw_string_outline(font, tp + Vector2(18, -10), "x%.1f" % reticle.damage_multiplier,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
		draw_string(font, tp + Vector2(18, -10), "x%.1f" % reticle.damage_multiplier,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, reticle.color_locked)


## 只画四个角的方括号，比整框更像瞄准镜。
func _draw_brackets(r: Rect2, col: Color, width: float) -> void:
	var l: float = minf(r.size.x, r.size.y) * 0.3
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var dirs: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i: int in 4:
		var p: Vector2 = corners[i]
		draw_line(p, p + Vector2(dirs[i].x * l, 0), col, width)
		draw_line(p, p + Vector2(0, dirs[i].y * l), col, width)
