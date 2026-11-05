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
## 飞过镜头（世界 Z 超过这个值）后自动销毁。
@export var despawn_z: float = 26.0
## 横向/纵向飞出这个范围（世界 |X| 或 |Y|）后自动销毁。
@export var despawn_xy: float = 40.0

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

	var p: Vector3 = global_position
	if _time >= max_lifetime or p.z > despawn_z or absf(p.x) > despawn_xy or absf(p.y) > despawn_xy:
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
