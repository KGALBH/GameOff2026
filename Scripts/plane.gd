class_name PlayerPlane
extends RigidBody3D
## 双翼尖推进器飞机。
## 机身持续受到沿机身"上"方向的主推力 up_force。
## 每侧推进器在翼尖处沿机身"下"方向施力（Shift = 把这一侧往下压）：
## - 单侧推进 → 力偏离质心产生扭矩 → 飞机翻滚（左压 → 左翼下沉 → 向左滚）
## - 双侧推进 → 扭矩抵消 → 抵消一部分主推力，整体向机腹方向沉
## 松开后，不倒翁回正力矩会把飞机慢慢扳回水平。
## 飞机只在 XY 平面内运动、只绕 Z 轴翻滚（其余轴已在场景里锁定）。

## 单个推进器的推力（牛）。两个一起 > 重力(mass*9.8) 才能上升。
@export var thrust_force: float = 15
## 推进器离机身中心线的距离（米），越大单侧推进时翻滚越猛。
@export var thruster_offset: float = 2.5
## 翻滚角速度上限（弧度/秒），防止转成陀螺。
@export var max_roll_speed: float = 1.0

@export var up_force: float = 10
## 只按一侧时的推力倍率（加大马力）。两侧一起按时按 1 倍计算。
@export var single_side_boost: float = 1.6
## 自动回正强度（不倒翁）：回正力矩 = 翻滚角(弧度) × 该值。
## 单侧推进器力矩 = thrust_force × thruster_offset（现在约 11.25），
## 回正强度要小于它才能把飞机压到大角度；设为 0 关闭回正。
@export var righting_strength: float = 4.0

@onready var _flame_left: Node3D = $FlameLeft
@onready var _flame_right: Node3D = $FlameRight


## 按空格快速翻面：在一侧翼尖沿机身"下"方向施加的一次性冲量大小。
## 越大翻得越快、越远；转多少度完全由物理（冲量、阻尼）决定。
@export var flip_impulse: float = 5

## 翻面状态：_flip_requested = 按了空格等物理帧处理；_flipping = 翻面中（不受 max_roll_speed 限制）。
var _flip_requested: bool = false
var _flipping: bool = false
## 翻面时是否把飞机定在原地（只转不动）。
@export var hold_position_while_flipping: bool = true
## 翻面开始时记下的位置，翻面期间一直钉在这里。
var _flip_anchor: Vector3

## 出生点（进入场景时的位置和姿态），按 R 回到这里。
var _spawn_transform: Transform3D
var _reset_requested: bool = false


## —— 俯仰表现（纯视觉，只转模型，不影响物理/碰撞）——
## 上升时机头朝上、下降时机头朝下。
## 每 1 米/秒 的升降速度对应多少度俯仰。
@export var pitch_per_speed: float = 4.0
## 最大俯仰角（度）。
@export var max_pitch_deg: float = 25.0
## 俯仰跟随速度，越大越灵敏、越小越柔和。
@export var pitch_smoothing: float = 6.0

## —— 自动射击：机头炮 ——
## 机头炮是否自动开火。
@export var auto_fire: bool = true
## 机头炮子弹场景。
@export var head_bullet_scene: PackedScene = preload("res://Scenes/bullet.tscn")
## 机头炮两发间隔（秒）。
@export var fire_interval: float = 0.05
## 机头枪口位置（相对机身，机头朝 -Z）。
@export var muzzle_offset: Vector3 = Vector3(0, 0, -2.8)
var _fire_timer: float = 0.0

## —— 自动射击：翼尖炮（左右机翼各一门，同时开火）——
## 翼尖炮是否自动开火。
@export var wing_auto_fire: bool = true
## 翼尖炮子弹场景。
@export var wing_bullet_scene: PackedScene = preload("res://Scenes/wing_bullet.tscn")
## 翼尖炮两发间隔（秒） 。
@export var wing_fire_interval: float = 0.20
## 右翼尖枪口位置（左翼自动取 X 镜像）。
@export var wing_muzzle_offset: Vector3 = Vector3(2.5, 0, -0.8)
var _wing_fire_timer: float = 0.0

## 翻面时翼尖弹的飞行速度（沿机翼向外，米/秒；翻面时不带向前的速度）。
@export var flip_spread_speed: float = 20.0
## 翻面时翼尖炮的射速倍率（2 = 射速翻倍）。
@export var flip_fire_rate_multiplier: float = 5.0

@onready var _model: Node3D = $Model
var _model_base: Transform3D
var _pitch: float = 0.0


## 受到伤害（敌机碰撞等调用）。现在只发信号，血量以后再做。
func take_hit(source: Node) -> void:
	SignalBus.player_hit.emit(source)


func _ready() -> void:
	_spawn_transform = global_transform
	_model_base = _model.transform


func _process(delta: float) -> void:
	# 用沿机身"上"方向的速度：正着飞时就是世界里的上升/下降；
	# 翻过来后也是机头朝运动方向偏，看起来更自然。
	var climb_speed: float = linear_velocity.dot(global_basis.y)
	var max_pitch: float = deg_to_rad(max_pitch_deg)
	var target: float = clampf(climb_speed * deg_to_rad(pitch_per_speed), -max_pitch, max_pitch)
	_pitch = lerpf(_pitch, target, 1.0 - exp(-pitch_smoothing * delta))
	# 机头朝 -Z，绕机身 X 轴正转 = 抬头
	_model.transform = Transform3D(Basis(Vector3.RIGHT, _pitch), Vector3.ZERO) * _model_base

	if auto_fire and head_bullet_scene:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer += fire_interval
			_spawn_bullet(head_bullet_scene, muzzle_offset)

	if wing_auto_fire and wing_bullet_scene:
		# 翻面时射速加快
		var interval: float = wing_fire_interval
		if _flipping:
			interval /= maxf(flip_fire_rate_multiplier, 0.01)
		# 刚开始翻面时不用等完普通间隔，立刻进入快速射击
		_wing_fire_timer = minf(_wing_fire_timer, interval) - delta
		if _wing_fire_timer <= 0.0:
			_wing_fire_timer += interval
			if _flipping:
				# 翻面时：取消向前的速度，只沿机翼向外射。机身在转，所以子弹会洒向四周一圈
				_spawn_bullet(wing_bullet_scene, wing_muzzle_offset, global_basis.x * flip_spread_speed, false)
				_spawn_bullet(wing_bullet_scene, wing_muzzle_offset * Vector3(-1, 1, 1), -global_basis.x * flip_spread_speed, false)
			else:
				_spawn_bullet(wing_bullet_scene, wing_muzzle_offset)
				_spawn_bullet(wing_bullet_scene, wing_muzzle_offset * Vector3(-1, 1, 1))


## 在机身局部坐标 local_offset 处，沿机身前方（不含俯仰表现）发射一颗子弹，
## extra_velocity 会叠加到子弹的飞行速度上；forward = false 时不带向前的速度，只用 extra_velocity。
func _spawn_bullet(scene: PackedScene, local_offset: Vector3, extra_velocity: Vector3 = Vector3.ZERO, forward: bool = true) -> void:
	var bullet: Bullet = scene.instantiate() as Bullet
	bullet.shooter = self
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = Transform3D(global_basis.orthonormalized(), global_transform * local_offset)
	var forward_velocity: Vector3 = -bullet.global_basis.z * bullet.speed if forward else Vector3.ZERO
	bullet.velocity = forward_velocity + extra_velocity

 
## 左右推进器的按键状态（不用 Input.is_action_pressed，原因见 _input）。
var _left_held: bool = false
var _right_held: bool = false


func _input(event: InputEvent) -> void:
	# Windows 长按会发 echo（连发）事件，偶尔有一个迟到、排在"松开"后面，会让推进器卡住。
	# 但按住一侧再按另一侧时，第二侧的真实按下也会被 Windows 标成 echo。
	# 所以规则是：两侧都没按着时来的 echo 一定是迟到的，丢掉；其余正常处理。
	if event is InputEventKey and event.echo and not _left_held and not _right_held:
		return
	if event.is_action("shift_left"):
		_left_held = event.is_pressed()
	elif event.is_action("shift_right"):
		_right_held = event.is_pressed()


func _notification(what: int) -> void:
	# 切出窗口时可能收不到松开事件，直接全部松开
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_left_held = false
		_right_held = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		_reset_requested = true
	elif event.is_action_pressed("space") and not _flipping:
		_flip_requested = true


func _physics_process(_delta: float) -> void:
	var left_on: bool = _left_held
	var right_on: bool = _right_held

	var down: Vector3 = -global_basis.y
	var up: Vector3 = global_basis.y
	var right_dir: Vector3 = global_basis.x

	# 翻面定身期间、或只按住一侧 Shift 时，不施加主推力（上升的力）；两侧同时按住时照常施加
	var frozen: bool = _flipping and hold_position_while_flipping
	var single_side: bool = left_on != right_on
	if not frozen and not single_side:
		if abs(rotation.z) < 2:
			apply_force(up * up_force)
		else:
			apply_force(down * up_force)
	
	# 只按一侧时加大马力
	var boost: float = single_side_boost if left_on != right_on else 1.0
	var force: float = thrust_force * boost

	if left_on:
		apply_force(down * force, -right_dir * thruster_offset)
	if right_on:
		apply_force(down * force, right_dir * thruster_offset)

	_flame_left.visible = left_on
	_flame_right.visible = right_on
	# 火焰跟着推力倍率变长，让玩家看得出在加大马力
	_flame_left.scale = Vector3(1.0, boost, 1.0)
	_flame_right.scale = Vector3(1.0, boost, 1.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# 刚体不能直接改 transform，要在物理回调里通过 state 重置
	if _reset_requested:
		_reset_requested = false
		state.transform = _spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_flipping = false
		_flip_requested = false
		return
 
	# 快速翻面：在一侧翼尖往下打一个大冲量。
	# 顺着当前翻滚方向：正在往左滚（+）就压左翼尖，往右滚（-）就压右翼尖；几乎没在转时默认压左翼尖。
	if _flip_requested:
		_flip_requested = false
		_flipping = true
		_flip_anchor = state.transform.origin
		var basis_now: Basis = state.transform.basis
		var side: float = -1.0 if state.angular_velocity.z >= -0.1 else 1.0  # -1 = 左翼尖，+1 = 右翼尖
		state.apply_impulse(-basis_now.y * flip_impulse, basis_now.x * side * thruster_offset)

	var av: Vector3 = state.angular_velocity
	if _flipping:
		# 定在原地：每个物理帧把位置钉回锚点、清掉线速度（重力和推力都不会让它移动）
		if hold_position_while_flipping:
			var t: Transform3D = state.transform
			t.origin = _flip_anchor
			state.transform = t
			state.linear_velocity = Vector3.ZERO
		# 翻面期间不限速，等阻尼把角速度降回正常范围后恢复限速
		if absf(av.z) <= max_roll_speed:
			_flipping = false
		return
   
	av.z = clampf(av.z, -max_roll_speed, max_roll_speed)
	state.angular_velocity = av
