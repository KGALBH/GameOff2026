class_name Bullet
extends Area3D
## 子弹：撞到物体或超过寿命后消失。
## - 有 target（瞄准框锁定的敌机）：追踪飞向目标，转向速度受 homing_turn_rate 限制。
## - 没有 target（比如翻面时向外散射，或目标中途死了）：按 velocity 直线飞，同时跟着发射者在画面里（XY）平移。

## 飞行速度（米/秒）。
@export var speed: float = 60.0
## 存活时间（秒），超时自动销毁。
@export var lifetime: float = 3.0
## 基础伤害（发射时会乘上瞄准框的伤害倍率）。
@export var damage: float = 1.0
## 追踪转向速度（弧度/秒），越大追得越紧。
@export var homing_turn_rate: float = 12.0

## 发射者（不会打到自己）。
var shooter: Node = null
## 追踪目标。
var target: Node3D = null
## 当前飞行速度（世界坐标）。为零时按 speed 沿自身前方飞。
var velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
## 是否是追踪弹（发射时带了目标）。
var _homing: bool = false
## 发射者上一帧的位置（无目标的子弹跟随平移用）。
var _shooter_last_pos: Vector3
var _has_last_pos: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if shooter is Node3D:
		_shooter_last_pos = (shooter as Node3D).global_position
		_has_last_pos = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	# 放在第一帧再算：发射者是在 add_child 之后才设置朝向的
	if velocity == Vector3.ZERO:
		velocity = -global_basis.z * speed
	# 发射者是在 add_child 之后才设置 target 的，所以在这里记下"我是追踪弹"
	if is_instance_valid(target):
		_homing = true
	# 追踪的目标没了（被打爆了）：改追飞机当前锁定的新目标；没有新目标就直接消失，
	# 不让它变成直线乱飞、散落在画面各处
	if _homing and (target == null or not is_instance_valid(target)):
		target = _shooter_current_target()
		if target == null:
			queue_free()
			return
	if target:
		_fly_homing(delta)
	else:
		_fly_free(delta)


## 发射者瞄准框当前锁定的目标（没有则为 null）。
func _shooter_current_target() -> Node3D:
	if not is_instance_valid(shooter):
		return null
	var aim: Node = shooter.get_node_or_null(^"AimReticle")
	if aim == null:
		return null
	var t: Variant = aim.get("target")
	return t as Node3D if is_instance_valid(t) else null


## 追踪：把速度方向逐渐转向目标。
func _fly_homing(delta: float) -> void:
	var to_target: Vector3 = target.global_position - global_position
	if to_target.length() > 0.001:
		var desired: Vector3 = to_target.normalized()
		var current: Vector3 = velocity.normalized()
		var angle: float = current.angle_to(desired)
		var step: float = minf(1.0, homing_turn_rate * delta / maxf(angle, 0.0001))
		velocity = current.slerp(desired, step) * speed
	global_position += velocity * delta
	_face(velocity)


## 普通飞行：按 velocity 飞，同时跟着发射者在画面里平移。
func _fly_free(delta: float) -> void:
	global_position += velocity * delta
	var shooter_3d: Node3D = shooter as Node3D if is_instance_valid(shooter) else null
	if shooter_3d:
		var sp: Vector3 = shooter_3d.global_position
		if _has_last_pos:
			var moved: Vector3 = sp - _shooter_last_pos
			global_position += Vector3(moved.x, moved.y, 0.0)
		_shooter_last_pos = sp
		_has_last_pos = true


func _face(dir: Vector3) -> void:
	if dir.length() > 0.001:
		var up: Vector3 = Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.99 else Vector3.BACK
		look_at(global_position + dir, up)


## 打中敌机：扣血并销毁子弹。
func _on_area_entered(area: Area3D) -> void:
	if area is Enemy:
		(area as Enemy).take_damage(damage)
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	queue_free()
