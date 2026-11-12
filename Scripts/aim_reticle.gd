class_name AimReticle
extends Node
## 自动瞄准框（挂在玩家飞机下面）。
## - 瞄准框在飞机周围一个固定的圆形范围里移动，像一个挂在飞机上的小重物：
##   主推力把它轻轻推向机身"上"方向；玩家按 Shift（手动推进器）会用力推它：
##   只按左 → 往机身左边，只按右 → 往机身右边，两侧一起 → 往机身下方。
##   飞机往哪边倾斜，推的方向就跟着转；飞机突然加速时框会被甩向反方向。
## - 判定按画面：敌机投影到屏幕上落在框内、且深度距离不超过 max_depth，就算锁定。框内有多个时锁定平面距离最近的。
## - 锁定后框不再受飞机推力影响，而是咬住目标跟着走；目标跑出圆形范围、射程或被打爆才脱锁，恢复受力移动。
## - 伤害按平面距离（只看 XY，不管深度）：离得越近倍率越高。
## 飞机读取 target / damage_multiplier 决定要不要开火、打多疼。

## —— 移动范围 ——
## 瞄准框中心能离开飞机的最大距离（米，在飞机所在深度上量）。
@export var circle_radius: float = 6.0
## 瞄准框的半边长（米，在飞机所在深度上量）。
@export var box_half_size: float = 3.5

@export_group("受力")
## 主推力（一直开着、沿机身"上"方向）推框的力度。故意弱一点，框平时只略微探向机头上方。
@export var tilt_push: float = 30.0
## 玩家手动推进器（Shift）推框的力度。单侧往该侧推，两侧一起往下推（按两份算）。比主推力强得多。
@export var manual_push: float = 70.0
## 把框拉回飞机的弹簧强度。tilt_push / spring = 不按键时框探出去的距离。
@export var spring: float = 3.0
## 阻尼，越大框越稳、越不晃。
@export var damping: float = 2.0
## 惯性：飞机加速时框被甩向反方向的程度。
@export var inertia: float = 0.0
## 锁定后框追目标的速度，越大咬得越紧。
@export var track_speed: float = 12.0

@export_group("锁定与伤害")
## 只锁定深度距离在这个范围内的敌机（米）。
@export var max_depth: float = 80.0
## 平面距离为 0 时的伤害倍率。
@export var damage_mult_near: float = 3.0
## 平面距离 ≥ damage_falloff 时的伤害倍率。
@export var damage_mult_far: float = 1.0
## 伤害倍率从 near 降到 far 所用的平面距离（米）。
@export var damage_falloff: float = 20.0

@export_group("显示")
@export var show_overlay: bool = true
@export var color_idle: Color = Color(0.6, 1.0, 0.9, 0.7)
@export var color_locked: Color = Color(1.0, 0.3, 0.25, 0.95)
@export var color_circle: Color = Color(1, 1, 1, 0.15)

## 当前锁定的敌机（没有则为 null）。
var target: Node3D = null
## 打当前目标时的伤害倍率。
var damage_multiplier: float = 1.0
## 瞄准框中心相对飞机的偏移（世界 XY，米）。
var offset: Vector2 = Vector2.ZERO

var _vel: Vector2 = Vector2.ZERO
var _last_plane_vel: Vector2 = Vector2.ZERO
var _plane: RigidBody3D
var _overlay: Control


func _ready() -> void:
	_plane = get_parent() as RigidBody3D
	if _plane:
		offset = _plane_up() * (tilt_push / maxf(spring, 0.01))
		offset = offset.limit_length(circle_radius)
	if show_overlay:
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 15  # 在像素滤镜（layer 10）之上，线条保持清晰
		add_child(layer)
		_overlay = preload("res://Scripts/aim_overlay.gd").new()
		_overlay.set("reticle", self)
		layer.add_child(_overlay)


func _physics_process(delta: float) -> void:
	if _plane == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	# 目标被打爆后变成"已释放"的对象，不能再传给带类型的参数，先清掉
	if not is_instance_valid(target):
		target = null
	# 已锁定：框不再受飞机推力影响，改为咬住目标；目标离开圆形范围 / 射程 / 框时才脱锁
	if target and _is_lockable(target, cam) and _track_target(delta, cam):
		_update_damage()
		return
	target = null
	_update_motion(delta)
	_update_target(cam)


## 锁定状态：把框中心移到"目标在飞机深度上的投影点"（画面上框对准目标）。
## 返回 false 表示追不上（目标跑出了圆形范围或框），需要脱锁。
func _track_target(delta: float, cam: Camera3D) -> bool:
	var desired: Vector2 = _screen_point_to_offset(cam, target.global_position)
	offset = offset.lerp(desired, 1.0 - exp(-track_speed * delta))
	_vel = Vector2.ZERO
	# 记下飞机速度，脱锁那一帧不会因为"突然的加速度"把框甩飞
	_last_plane_vel = Vector2(_plane.linear_velocity.x, _plane.linear_velocity.y)
	if offset.length() > circle_radius:
		offset = offset.normalized() * circle_radius
	return box_screen_rect(cam).has_point(cam.unproject_position(target.global_position))


## 世界点 p 在画面上的位置，换算成"飞机深度平面上相对飞机的偏移"。
func _screen_point_to_offset(cam: Camera3D, p: Vector3) -> Vector2:
	var eye: Vector3 = cam.global_position
	var pz: float = _plane.global_position.z
	var t: float = (eye.z - pz) / maxf(eye.z - p.z, 0.01)
	var on_plane: Vector3 = eye + (p - eye) * t
	return Vector2(on_plane.x - _plane.global_position.x, on_plane.y - _plane.global_position.y)


## 敌机能不能被锁定（存在、可见、在射程内、在摄像机前方）。
func _is_lockable(e: Node3D, cam: Camera3D) -> bool:
	if e == null or not is_instance_valid(e) or not e.is_inside_tree() or not e.is_visible_in_tree():
		return false
	var depth: float = _plane.global_position.z - e.global_position.z
	if depth > max_depth or depth < -max_depth * 0.1:
		return false
	return not cam.is_position_behind(e.global_position)


## 按平面距离算伤害倍率。
func _update_damage() -> void:
	var pp: Vector3 = _plane.global_position
	var d: float = Vector2(target.global_position.x - pp.x, target.global_position.y - pp.y).length()
	var f: float = clampf(d / maxf(damage_falloff, 0.01), 0.0, 1.0)
	damage_multiplier = lerpf(damage_mult_near, damage_mult_far, f)


## 瞄准框的受力移动：推力（倾斜方向）+ 弹簧 + 阻尼 + 惯性，限制在圆形范围内。
func _update_motion(delta: float) -> void:
	var pv: Vector2 = Vector2(_plane.linear_velocity.x, _plane.linear_velocity.y)
	var plane_acc: Vector2 = (pv - _last_plane_vel) / maxf(delta, 0.0001)
	_last_plane_vel = pv
	# 主推力：沿机身上方（弱）
	var push: Vector2 = _plane_up() * tilt_push
	# 手动推进器（强）：只按左 → 推向机身左边；只按右 → 推向机身右边；两侧一起 → 推向机身下方
	var sides: Vector2i = _plane.call(&"manual_thrust_sides") if _plane.has_method(&"manual_thrust_sides") else Vector2i.ZERO
	if sides.x == 1 and sides.y == 1:
		push -= _plane_up() * manual_push * 2.0
	elif sides.x == 1:
		push -= _plane_right() * manual_push
	elif sides.y == 1:
		push += _plane_right() * manual_push
	var acc: Vector2 = push - offset * spring - _vel * damping - plane_acc * inertia
	_vel += acc * delta
	offset += _vel * delta
	# 碰到圆边：贴着边，去掉向外的速度
	if offset.length() > circle_radius:
		var n: Vector2 = offset.normalized()
		offset = n * circle_radius
		var outward: float = _vel.dot(n)
		if outward > 0.0:
			_vel -= n * outward


func _plane_up() -> Vector2:
	var up: Vector3 = _plane.global_basis.y
	return Vector2(up.x, up.y).normalized()


func _plane_right() -> Vector2:
	var r: Vector3 = _plane.global_basis.x
	return Vector2(r.x, r.y).normalized()


## 瞄准框中心的世界坐标。
func box_center_world() -> Vector3:
	return _plane.global_position + Vector3(offset.x, offset.y, 0.0)


## 瞄准框在屏幕上的矩形。
func box_screen_rect(cam: Camera3D) -> Rect2:
	var c: Vector3 = box_center_world()
	var a: Vector2 = cam.unproject_position(c + Vector3(-box_half_size, box_half_size, 0))
	var b: Vector2 = cam.unproject_position(c + Vector3(box_half_size, -box_half_size, 0))
	return Rect2(a, b - a).abs()


## 未锁定时：在框里找平面距离最近的可锁定敌机。
func _update_target(cam: Camera3D) -> void:
	damage_multiplier = 1.0
	var rect: Rect2 = box_screen_rect(cam)
	var pp: Vector3 = _plane.global_position
	var best_d: float = INF
	for n: Node in get_tree().get_nodes_in_group(&"enemies"):
		var e: Node3D = n as Node3D
		if not _is_lockable(e, cam):
			continue
		if not rect.has_point(cam.unproject_position(e.global_position)):
			continue
		var d: float = Vector2(e.global_position.x - pp.x, e.global_position.y - pp.y).length()
		if d < best_d:
			best_d = d
			target = e
	if target:
		_update_damage()
