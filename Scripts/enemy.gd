class_name Enemy
extends Area3D
## 敌机模板。
## - 外观：设置 model_scene 换模型（不设就用场景里自带的占位模型）。
## - 轨迹：沿 direction 方向以 speed 前进，再叠加 pattern 指定的横向摆动。
##   从屏幕深处飞出来：direction = (0, 0, 1)；从左边飞进来：direction = (1, 0, 0)，依此类推。
## - 碰到玩家：发 SignalBus.enemy_hit_player 并调用玩家的 take_hit()，然后自己销毁。
## - 被子弹打：扣 hp，归零后发 SignalBus.enemy_died 并销毁。
## 编队（数量、阵型）由 EnemyFormation 负责，单个敌机也可以直接摆进场景使用。

## 轨迹样式（定义在 EnemyPath，这里留个别名，Enemy.Pattern.SINE 这种写法照样能用）。
const Pattern = EnemyPath.Pattern

@export_group("外观")
## 敌机模型（.tscn / .blend / .glb 都行）。留空则使用自带的占位模型。
@export var model_scene: PackedScene

@export_group("轨迹")
## 前进方向（世界坐标）。(0,0,1) = 从深处朝屏幕外飞。
@export var direction: Vector3 = Vector3(0, 0, 1)
## 前进速度（米/秒）。
@export var speed: float = 15.0
## 横向摆动的样式。
@export var pattern: EnemyPath.Pattern = EnemyPath.Pattern.STRAIGHT
## 摆动幅度（米）。
@export var amplitude: float = 4.0
## 摆动频率（每秒几个来回）。
@export var frequency: float = 0.5
## 摆动起始相位（0~1），同一编队里错开相位可以做出波浪。
@export_range(0.0, 1.0) var phase: float = 0.0
## 模型是否自动朝向飞行方向。
@export var face_movement: bool = true

@export_group("战斗")
## 生命值（被几发子弹打中才爆）。
@export var hp: int = 3
## 存活上限（秒），超时自动销毁，防止飞出画面后一直残留。
@export var max_lifetime: float = 40.0
## 朝屏幕飞来的敌机，飞过玩家所在平面（世界 Z 超过这个值）后立刻销毁。
## 只对朝 +Z 飞的敌机生效，在 z = 0 平面里横飞的敌机不受影响。
@export var despawn_z: float = 3.0
## 横向/纵向飞出这个范围（世界 |X| 或 |Y|）后自动销毁。
@export var despawn_xy: float = 40.0

@export_group("可读性")
## 显示落点标记：在玩家所在平面（z = 0）上画一个圈，标出这架敌机将会穿过的位置。
@export var show_landing_marker: bool = true
## 到达前多少秒开始显示落点圈。
@export var marker_lead_time: float = 2.0
## 落点圈刚出现时的放大倍数（到达时缩到 1 倍 = 碰撞大小）。
@export var marker_start_scale: float = 3.0
## 落点圈颜色（透明度会随接近程度变化）。
@export var marker_color: Color = Color(1.0, 0.35, 0.2)
## 按距离变色：越远越偏向 tint_color（像雾一样发灰发蓝），越近越接近原色。
@export var distance_tint: bool = true
## 距玩家平面多近开始完全是原色（米）。
@export var tint_near: float = 15.0
## 距玩家平面多远达到最大染色（米）。
@export var tint_far: float = 120.0
## 远处的颜色。
@export var tint_color: Color = Color(0.45, 0.55, 0.75)
## 最远处染色的强度（0~1）。
@export_range(0.0, 1.0) var tint_max: float = 0.8

## 出发前的等待时间（秒），编队用它做"一架接一架"的效果。
var start_delay: float = 0.0
## 编队生成时指定的出发点（世界坐标）。为 null 时用敌机自己摆放的位置。
var spawn_global_position: Variant = null
## 被移除时回调 on_removed.call(killed: bool)：killed = 被打爆，false = 撞玩家/飞走。编队用它统计。
var on_removed: Callable

var _origin: Vector3
var _time: float = 0.0
var _side: Vector3
var _up: Vector3
var _removed: bool = false

## 落点：穿过 z = 0 的时刻（飞行时间，<0 表示不会穿过）和位置。
var _cross_time: float = -1.0
var _cross_pos: Vector3
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _tint_mat: StandardMaterial3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if model_scene:
		for child: Node in $Model.get_children():
			child.queue_free()
		$Model.add_child(model_scene.instantiate())
	if spawn_global_position != null:
		global_position = spawn_global_position
	_origin = global_position
	direction = EnemyPath.forward(direction)
	_side = EnemyPath.side_axis(direction)
	_up = EnemyPath.up_axis(direction, _side)
	# 等待出发期间先藏起来、不检测碰撞
	if start_delay > 0.0:
		_set_active(false)
	_update_transform(0.0)
	_setup_readability()


## 等待出发时隐藏，且既不撞玩家、也不会被子弹打到。
func _set_active(on: bool) -> void:
	visible = on
	set_deferred("monitoring", on)
	set_deferred("monitorable", on)


func _physics_process(delta: float) -> void:
	if start_delay > 0.0:
		start_delay -= delta
		if start_delay > 0.0:
			return
		_set_active(true)

	_time += delta
	_update_transform(delta)
	_update_readability()

	var p: Vector3 = global_position
	var passed_player: bool = direction.z > 0.01 and p.z > despawn_z
	if _time >= max_lifetime or passed_player or absf(p.x) > despawn_xy or absf(p.y) > despawn_xy:
		_remove(false)


## 按时间计算位置：沿前进方向走 + 横向摆动。
func _update_transform(delta: float) -> void:
	var prev: Vector3 = global_position
	global_position = _origin + direction * speed * _time + _offset_at(_time)
	if face_movement and delta > 0.0:
		var move: Vector3 = global_position - prev
		if move.length() > 0.0001:
			var up_hint: Vector3 = Vector3.UP if absf(move.normalized().dot(Vector3.UP)) < 0.99 else Vector3.BACK
			look_at(global_position + move, up_hint)


func _offset_at(t: float) -> Vector3:
	return EnemyPath.wobble(pattern, amplitude, frequency, phase, t, _side, _up)


## 飞行 t 秒时的位置（和 _update_transform 用同一个公式）。
func _path_pos(t: float) -> Vector3:
	return _origin + direction * speed * t + _offset_at(t)


# ———————————— 可读性：落点标记 + 距离染色 ————————————

func _setup_readability() -> void:
	if show_landing_marker:
		_cross_time = _solve_cross_time()
		if _cross_time > 0.0:
			_cross_pos = _path_pos(_cross_time)
			_cross_pos.z = 0.0
			_marker = _create_marker()
			add_child(_marker)
			_marker.visible = false

	if distance_tint:
		# 用 material_overlay 叠一层半透明的颜色，换了 model_scene 也能用
		_tint_mat = StandardMaterial3D.new()
		_tint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for node: Node in $Model.find_children("*", "MeshInstance3D", true, false):
			if not node.is_queued_for_deletion():
				(node as MeshInstance3D).material_overlay = _tint_mat
		_update_tint()


## 计算穿过 z = 0 的飞行时间。不朝玩家方向飞（比如横着飞）返回 -1。
func _solve_cross_time() -> float:
	var vz: float = direction.z * speed
	if vz < 0.5 or _origin.z >= 0.0:
		return -1.0
	# 先按直线估算，再用牛顿法修正摆动带来的 z 偏差
	var t: float = -_origin.z / vz
	for i: int in 4:
		t -= _path_pos(t).z / vz
	return t


func _create_marker() -> MeshInstance3D:
	var ring: TorusMesh = TorusMesh.new()
	var radius: float = 0.85
	var shape: CollisionShape3D = get_node_or_null(^"Shape") as CollisionShape3D
	if shape and shape.shape is SphereShape3D:
		radius = (shape.shape as SphereShape3D).radius
	ring.inner_radius = radius * 0.8
	ring.outer_radius = radius
	ring.rings = 24
	ring.ring_segments = 6

	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.no_depth_test = true
	_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_mat.render_priority = 10

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "LandingMarker"
	mi.mesh = ring
	mi.material_override = _marker_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true  # 不跟着敌机移动、旋转
	return mi


func _update_readability() -> void:
	if _marker:
		var time_left: float = _cross_time - _time
		if time_left > marker_lead_time or time_left < 0.0:
			_marker.visible = false
		else:
			# k：0 = 刚出现，1 = 正在穿过
			var k: float = 1.0 - time_left / maxf(marker_lead_time, 0.01)
			var s: float = lerpf(marker_start_scale, 1.0, k)
			# 圆环默认躺在 XZ 平面，转 90° 立起来，正对镜头
			_marker.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * s), _cross_pos)
			var c: Color = marker_color
			c.a = lerpf(0.15, 0.9, k)
			_marker_mat.albedo_color = c
			_marker.visible = true
	if _tint_mat:
		_update_tint()


func _update_tint() -> void:
	var dist: float = -global_position.z
	var f: float = clampf((dist - tint_near) / maxf(tint_far - tint_near, 0.01), 0.0, 1.0)
	var c: Color = tint_color
	c.a = f * tint_max
	_tint_mat.albedo_color = c


## 被子弹击中。
func take_damage(amount: int) -> void:
	if _removed:
		return
	hp -= amount
	if hp <= 0:
		SignalBus.enemy_died.emit(self)
		_remove(true)


func _on_body_entered(body: Node3D) -> void:
	if _removed:
		return
	if body is PlayerPlane:
		SignalBus.enemy_hit_player.emit(self, body)
		(body as PlayerPlane).take_hit(self)
		_remove(false)


## 统一的移除出口：只通知一次编队，然后销毁。
func _remove(killed: bool) -> void:
	if _removed:
		return
	_removed = true
	if on_removed.is_valid():
		on_removed.call(killed)
	queue_free()
