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

@export var up_force: float = 17
## 只按一侧时的推力倍率（加大马力）。两侧一起按时按 1 倍计算。
@export var single_side_boost: float = 1.6
## 自动回正强度（不倒翁）：回正力矩 = 翻滚角(弧度) × 该值。
## 单侧推进器力矩 = thrust_force × thruster_offset（现在约 11.25），
## 回正强度要小于它才能把飞机压到大角度；设为 0 关闭回正。
@export var righting_strength: float = 4.0


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

## —— 生命（避障：撞到障碍扣一条命）——
## 一共几条命。
@export var max_lives: int = 3
## 被撞后的无敌时间（秒），期间飞机闪烁、不会再扣命。
@export var invincible_time: float = 1.5

## 当前剩几条命。
var lives: int
## 是否已经撞毁（命用完了）。
var dead: bool = false
var _invincible_left: float = 0.0
var _hud: Label

@onready var _model: Node3D = $Model
var _model_base: Transform3D
var _pitch: float = 0.0


## 被障碍撞到（敌机等调用）：扣一条命，之后短暂无敌。命用完 → 撞毁判负。
## source 可以是撞到自己的节点，也可以是数字（队友的 EnemyPlane 会传伤害值）；不管是什么，都扣一条命。
func take_hit(source: Variant = null) -> void:
	if dead or _invincible_left > 0.0:
		return
	lives -= 1
	SignalBus.player_hit.emit(source as Node if source is Node else null)
	SignalBus.player_lives_changed.emit(lives)
	_invincible_left = invincible_time
	if lives <= 0:
		dead = true
		SignalBus.player_failed.emit("crashed")
	_update_hud()


## 回满命（按 R 重来时调用）。
func _restore_lives() -> void:
	lives = max_lives
	dead = false
	_invincible_left = 0.0
	_model.visible = true
	SignalBus.player_lives_changed.emit(lives)
	SignalBus.player_respawned.emit()
	_update_hud()


func _ready() -> void:
	_spawn_transform = global_transform
	_model_base = _model.transform
	add_to_group(&"player")  # 敌机靠这个组找玩家（擦边判定等）
	_build_hud()
	_restore_lives()


func _process(delta: float) -> void:
	# 用沿机身"上"方向的速度：正着飞时就是世界里的上升/下降；
	# 翻过来后也是机头朝运动方向偏，看起来更自然。
	var climb_speed: float = linear_velocity.dot(global_basis.y)
	var max_pitch: float = deg_to_rad(max_pitch_deg)
	var target: float = clampf(climb_speed * deg_to_rad(pitch_per_speed), -max_pitch, max_pitch)
	_pitch = lerpf(_pitch, target, 1.0 - exp(-pitch_smoothing * delta))
	# 机头朝 -Z，绕机身 X 轴正转 = 抬头
	_model.transform = Transform3D(Basis(Vector3.RIGHT, _pitch), Vector3.ZERO) * _model_base

	# 无敌期间闪烁
	if _invincible_left > 0.0:
		_invincible_left -= delta
		_model.visible = _invincible_left <= 0.0 or fmod(_invincible_left, 0.2) > 0.1


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20  # 在像素滤镜（layer 10）之上，文字保持清晰
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24, 16)
	_hud.add_theme_font_size_override(&"font_size", 28)
	_hud.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override(&"outline_size", 8)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null:
		return
	if dead:
		_hud.add_theme_color_override(&"font_color", Color(1, 0.3, 0.3))
		_hud.text = "生命  " + "□ ".repeat(max_lives)
	else:
		_hud.add_theme_color_override(&"font_color", Color.WHITE)
		_hud.text = "生命  " + "■ ".repeat(lives) + "□ ".repeat(max_lives - lives)


## 左右推进器的按键状态（不用 Input.is_action_pressed，原因见 _input）。
var _left_held: bool = false
var _right_held: bool = false
## 每侧最近一次"松开"的时间（毫秒），用来识别松开后迟到的 echo。
var _left_released_ms: int = -100000
var _right_released_ms: int = -100000
## 松开后多少毫秒内来的 echo 视为迟到的连发，丢掉。
const LATE_ECHO_MS = 150


func _input(event: InputEvent) -> void:
	# 兜底：任何带修饰键信息的事件（鼠标移动、其他按键…）都会如实报告系统里 Shift 是否按着。
	# 如果系统说"没有 Shift"，而我们还以为按着，说明漏掉了松开事件 → 强制松开，推进器不会卡住。
	if event is InputEventWithModifiers and not (event as InputEventWithModifiers).shift_pressed:
		var is_shift_press: bool = event is InputEventKey and (event as InputEventKey).pressed \
				and (event.is_action("shift_left") or event.is_action("shift_right"))
		if not is_shift_press:
			_left_held = false
			_right_held = false
	# 代码/测试里直接触发的动作（Input.action_press 等）没有 Windows 的那些坑，直接用
	if event is InputEventAction:
		if event.is_action("shift_left"):
			_left_held = event.is_pressed()
		elif event.is_action("shift_right"):
			_right_held = event.is_pressed()
		return
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	var is_left: bool = key.is_action("shift_left")
	var is_right: bool = key.is_action("shift_right")
	if not is_left and not is_right:
		return

	if key.pressed:
		if key.echo:
			# Windows 的两个坑：
			# 1. 长按时的 echo 偶尔迟到，排在"松开"后面 → 刚松开就来的 echo 要丢掉，否则推进器卡住。
			# 2. 按住一侧 Shift 再按另一侧，第二侧的真实按下会被标成 echo → 不能一律丢掉 echo。
			var released_ms: int = _left_released_ms if is_left else _right_released_ms
			if Time.get_ticks_msec() - released_ms < LATE_ECHO_MS:
				return
		if is_left:
			_left_held = true
		else:
			_right_held = true
	else:
		var now: int = Time.get_ticks_msec()
		if is_left:
			_left_held = false
			_left_released_ms = now
		else:
			_right_held = false
			_right_released_ms = now
		# 坑 3：两个 Shift 同时按着时先松开一个，Windows 经常不发它的松开事件，
		# 最后只收到一次松开。所以松开时如果系统已经没有任何 Shift 按着，就两侧一起松开。
		if not key.shift_pressed:
			_left_held = false
			_right_held = false
			_left_released_ms = now
			_right_released_ms = now



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

	apply_force(up * up_force)

	
	# 只按一侧时加大马力
	var boost: float = single_side_boost if left_on != right_on else 1.0
	var force: float = thrust_force * boost

	if left_on:
		apply_force(down * force, -right_dir * thruster_offset)
	if right_on:
		apply_force(down * force, right_dir * thruster_offset)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# 刚体不能直接改 transform，要在物理回调里通过 state 重置
	if _reset_requested:
		_reset_requested = false
		state.transform = _spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_restore_lives.call_deferred()
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
