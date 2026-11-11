@tool
class_name PlayArea
extends Node3D
## 可活动区域 + 摄像机轻微跟随 + 离开画面判负。
## - 跟随范围 = 摄像机在 plane_z 深度能看到的画面 × screen_scale（默认大 1/5）。不会挡住飞机。
## - 摄像机不缩放，只在这个范围里带延迟地轻微平移：飞机到达范围边缘时，摄像机刚好移到能看见那条边。
## - 飞机离开画面开始倒计时，连续 out_of_screen_limit 秒没回来就判负（SignalBus.player_failed）。
## 编辑器里会画出跟随范围（青色）和初始画面（白色）。

## 摄像机。
@export var camera: Camera3D
## 摄像机跟随的目标（玩家飞机）。
@export var target: Node3D
## 跟随范围比画面大多少倍（1.2 = 大 1/5）。
@export var screen_scale: float = 1.2
## 飞机所在的深度（世界 Z）。
@export var plane_z: float = 0.0

@export_group("摄像机跟随")
## 跟随程度：1 = 飞机到范围边缘时摄像机刚好看到那条边；0 = 不跟随。
@export_range(0.0, 1.0) var follow_amount: float = 1.0
## 跟随延迟（秒）：摄像机追的是飞机这么久之前的位置。
@export_range(0.0, 2.0) var follow_delay: float = 0.25
## 跟随平滑度，越小越"拖"、越大越跟手。
@export var follow_smoothing: float = 2.5
## 到范围边缘时摄像机额外多移的距离（米），让飞机整个机身都在画面内。
@export var edge_margin: float = 2.0

@export_group("离开画面判负")
## 离开画面多少秒判负。
@export var out_of_screen_limit: float = 5.0
## 显示"返回画面"倒计时提示。
@export var show_warning: bool = true

## 运行时算出的跟随范围半宽/半高，以及中心（世界 XY）。
var half_extents: Vector2
var center: Vector2
## 飞机已经离开画面多少秒（在画面里时为 0）。
var out_time: float = 0.0
## 是否已经判负。
var failed: bool = false

var _camera_base: Vector3
var _view_half: Vector2
var _preview_timer: float = 0.0
## 飞机位置历史 [时间, 位置]，用来实现跟随延迟。
var _history: Array[Vector4] = []
var _clock: float = 0.0
var _label: Label


func _ready() -> void:
	if Engine.is_editor_hint() or camera == null:
		return
	_camera_base = camera.global_position
	_recompute()
	get_viewport().size_changed.connect(_recompute)
	if show_warning:
		_build_warning_label()


## 根据摄像机视野算出画面和跟随范围大小。
func _recompute() -> void:
	var aspect: float = _aspect()
	var dist: float = absf(_camera_base.z - plane_z)
	var half_h: float = dist * tan(deg_to_rad(camera.fov) * 0.5)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		_view_half = Vector2(half_h, half_h / aspect)
	else:
		_view_half = Vector2(half_h * aspect, half_h)
	half_extents = _view_half * screen_scale
	center = Vector2(_camera_base.x, _camera_base.y)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_preview(delta)
		return
	if camera == null or target == null:
		return
	_update_camera(delta)
	_update_out_of_screen(delta)


func _update_camera(delta: float) -> void:
	_clock += delta
	var p: Vector3 = target.global_position
	_history.append(Vector4(_clock, p.x, p.y, p.z))
	# 取 follow_delay 秒之前的位置；更早的历史丢掉
	while _history.size() > 1 and _history[1].x <= _clock - follow_delay:
		_history.pop_front()
	var delayed: Vector2 = Vector2(_history[0].y, _history[0].z)

	# 飞机相对中心的位置 → 按比例换算成摄像机偏移，最大不超过"范围 - 画面"
	var max_offset: Vector2 = (half_extents - _view_half + Vector2.ONE * edge_margin) * follow_amount
	var rel: Vector2 = delayed - center
	var k: Vector2 = Vector2(
			max_offset.x / maxf(half_extents.x, 0.01),
			max_offset.y / maxf(half_extents.y, 0.01))
	var offset: Vector2 = (rel * k).clamp(-max_offset, max_offset)
	var desired: Vector3 = _camera_base + Vector3(offset.x, offset.y, 0.0)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-follow_smoothing * delta))


## 飞机是否还有任何一部分在画面里（宽松判定：哪怕只露出一个像素也算在画面内）。
## 做法：取飞机所有可见网格的包围盒，把 8 个角投影到屏幕，看投影出的矩形和屏幕有没有重叠。
func is_target_on_screen() -> bool:
	var screen: Rect2 = get_viewport().get_visible_rect()
	var box: AABB = _target_world_aabb()
	var min_p: Vector2 = Vector2(INF, INF)
	var max_p: Vector2 = Vector2(-INF, -INF)
	var any_in_front: bool = false
	for i: int in 8:
		var corner: Vector3 = box.get_endpoint(i)
		if camera.is_position_behind(corner):
			continue
		any_in_front = true
		var sp: Vector2 = camera.unproject_position(corner)
		min_p = min_p.min(sp)
		max_p = max_p.max(sp)
	if not any_in_front:
		return false
	return Rect2(min_p, max_p - min_p).intersects(screen, true)


## 飞机所有可见网格合起来的世界包围盒（没有网格时退化成一个点）。
func _target_world_aabb() -> AABB:
	var result: AABB = AABB(target.global_position, Vector3.ZERO)
	var first: bool = true
	var stack: Array[Node] = [target]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var vi: VisualInstance3D = n as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		var world_box: AABB = vi.global_transform * vi.get_aabb()
		result = world_box if first else result.merge(world_box)
		first = false
	return result


func _update_out_of_screen(delta: float) -> void:
	var bus: Node = get_node(^"/root/SignalBus")
	if is_target_on_screen():
		if out_time > 0.0:
			bus.emit_signal(&"player_returned_screen")
		out_time = 0.0
		# 判负后飞机回到画面（比如按 R 重置）就解除失败状态
		failed = false
	else:
		if out_time == 0.0 and not failed:
			bus.emit_signal(&"player_left_screen")
		out_time += delta
		if not failed and out_time >= out_of_screen_limit:
			failed = true
			bus.emit_signal(&"player_failed", "out_of_screen")
	_update_warning_label()


func _build_warning_label() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20  # 在像素滤镜（layer 10）之上，文字保持清晰
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.position.y = 40
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.add_theme_font_size_override(&"font_size", 36)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	layer.add_child(_label)


func _update_warning_label() -> void:
	if _label == null:
		return
	if failed:
		_label.visible = true
		_label.add_theme_color_override(&"font_color", Color(1, 0.3, 0.3))
		_label.text = "失败：离开画面太久
按 R 重来"
	elif out_time > 0.0:
		_label.visible = true
		_label.add_theme_color_override(&"font_color", Color(1, 0.85, 0.2))
		_label.text = "返回画面！ %.1f" % maxf(out_of_screen_limit - out_time, 0.0)
	else:
		_label.visible = false


func _aspect() -> float:
	if Engine.is_editor_hint():
		var w: float = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
		var h: float = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
		return w / maxf(h, 1.0)
	var s: Vector2 = get_viewport().get_visible_rect().size
	return s.x / maxf(s.y, 1.0)


# ———————————— 编辑器预览 ————————————

func _editor_preview(delta: float) -> void:
	_preview_timer -= delta
	if _preview_timer > 0.0:
		return
	_preview_timer = 0.3
	if camera == null:
		PathPreview.clear(self)
		return
	_camera_base = camera.global_position
	_recompute()
	var mi: MeshInstance3D = PathPreview.get_or_create(self)
	var im: ImmediateMesh = PathPreview.begin(mi)
	PathPreview.draw_lines(im, _rect_lines(half_extents), Color(0.2, 1.0, 1.0))
	PathPreview.draw_lines(im, _rect_lines(_view_half), Color(1, 1, 1, 0.6))


func _rect_lines(h: Vector2) -> PackedVector3Array:
	var z: float = plane_z
	var a: Vector3 = Vector3(center.x - h.x, center.y - h.y, z)
	var b: Vector3 = Vector3(center.x + h.x, center.y - h.y, z)
	var c: Vector3 = Vector3(center.x + h.x, center.y + h.y, z)
	var d: Vector3 = Vector3(center.x - h.x, center.y + h.y, z)
	return PackedVector3Array([a, b, b, c, c, d, d, a])
