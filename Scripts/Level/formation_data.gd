@tool
class_name FormationData
extends Resource
## 一个敌机编队的完整描述：用哪种敌机、几架、什么阵型、怎么飞。
## 存成 .tres 就能在不同关卡、不同波次里反复使用。

enum Shape {
	LINE,    ## 横排
	V,       ## V 字（人字）
	GRID,    ## 方阵
	CIRCLE,  ## 环形
	TRAIL,   ## 一路纵队：同一位置一架接一架出发
}

## 敌机场景（换不同敌机就换这个）。
@export var enemy_scene: PackedScene = preload("res://Scenes/enemy.tscn")
## 敌机数量。
@export_range(1, 64) var count: int = 5
## 阵型。
@export var shape: Shape = Shape.LINE
## 敌机间距（米）。
@export var spacing: float = 3.0
## 方阵每行几架（仅 GRID）。
@export_range(1, 16) var grid_columns: int = 3
## 每架之间的出发间隔（秒）。TRAIL 阵型靠它拉开距离；其他阵型设 0 就是同时出发。
@export var stagger: float = 0.0
## 每架之间的摆动相位差（0~1），配合 SINE/CIRCLE 做出波浪感。
@export_range(0.0, 1.0) var phase_step: float = 0.0

@export_group("轨迹覆盖")
## 勾选后用下面的参数覆盖敌机场景里的轨迹设置。
@export var override_movement: bool = false
## 前进方向。(0,0,1) = 从深处朝屏幕外；(1,0,0) = 从左往右；(0,-1,0) = 从上往下。
@export var direction: Vector3 = Vector3(0, 0, 1)
@export var speed: float = 15.0
@export var pattern: EnemyPath.Pattern = EnemyPath.Pattern.STRAIGHT
@export var amplitude: float = 4.0
@export var frequency: float = 0.5


## 第 i 架最终使用的轨迹参数（覆盖值或敌机场景里的值）。
func movement_for(i: int) -> Dictionary:
	var m: Dictionary = {}
	if override_movement:
		m.direction = direction
		m.speed = speed
		m.pattern = pattern
		m.amplitude = amplitude
		m.frequency = frequency
	else:
		m.direction = _enemy_default(&"direction", Vector3.BACK)
		m.speed = _enemy_default(&"speed", 15.0)
		m.pattern = _enemy_default(&"pattern", 0)
		m.amplitude = _enemy_default(&"amplitude", 4.0)
		m.frequency = _enemy_default(&"frequency", 0.5)
	var base_phase: float = _enemy_default(&"phase", 0.0)
	m.phase = fposmod(base_phase + phase_step * i, 1.0)
	m.delay = stagger * i
	return m


## 第 i 架在阵型里的偏移（在垂直于前进方向的平面内排列）。
func slot_offset(i: int, dir: Vector3) -> Vector3:
	var fwd: Vector3 = EnemyPath.forward(dir)
	var side: Vector3 = EnemyPath.side_axis(fwd)
	var up: Vector3 = EnemyPath.up_axis(fwd, side)
	# 从深处飞来的编队在画面里横向/纵向排开；从侧面飞来的编队沿前后方向排开
	var spread_b: Vector3 = up if absf(fwd.z) > 0.7 else -fwd

	var centered: float = i - (count - 1) * 0.5
	match shape:
		Shape.LINE:
			return side * centered * spacing
		Shape.V:
			# 0 号在最前面（领头），后面左右交替往后排
			var rank: int = floori((i + 1) / 2.0)
			var s: float = -1.0 if i % 2 == 1 else 1.0
			return side * s * rank * spacing - fwd * rank * spacing
		Shape.GRID:
			var rows: int = ceili(float(count) / grid_columns)
			var col: int = i % grid_columns
			var row: int = floori(float(i) / grid_columns)
			var cx: float = col - (grid_columns - 1) * 0.5
			var cy: float = row - (rows - 1) * 0.5
			return (side * cx + spread_b * cy) * spacing
		Shape.CIRCLE:
			var a: float = TAU * i / count
			var radius: float = spacing * count / TAU
			return (side * cos(a) + spread_b * sin(a)) * radius
	# TRAIL：全部从同一点出发，靠 stagger 拉开
	return Vector3.ZERO


## 第 i 架在出发后 t 秒（含等待 stagger）的世界位置。t 小于等待时间时停在出发点。
func position_at(i: int, origin: Vector3, t: float) -> Vector3:
	var m: Dictionary = movement_for(i)
	var start: Vector3 = origin + slot_offset(i, m.direction)
	var flying: float = maxf(t - m.delay, 0.0)
	return start + EnemyPath.displacement(m.direction, m.speed, m.pattern, m.amplitude,
			m.frequency, m.phase, flying)


## 运行时：生成第 i 架敌机（还没加进场景树）。origin 为编队中心的世界坐标。
## 用 set() 赋值而不直接写 Enemy 类型：这是 @tool 脚本，不依赖运行时脚本，编辑器预览更稳。
func create_enemy(i: int, origin: Vector3) -> Node3D:
	var enemy: Node3D = enemy_scene.instantiate() as Node3D
	var m: Dictionary = movement_for(i)
	for key: String in ["direction", "speed", "pattern", "amplitude", "frequency", "phase"]:
		enemy.set(key, m[key])
	enemy.set("start_delay", m.delay)
	enemy.set("spawn_global_position", origin + slot_offset(i, m.direction))
	return enemy


## 编辑器预览：把每架敌机 duration 秒内的飞行路线追加成线段（两两一对）。
func append_preview_lines(lines: PackedVector3Array, origin: Vector3, duration: float, step: float = 0.1) -> void:
	for i: int in count:
		var prev: Vector3 = position_at(i, origin, 0.0)
		var t: float = step
		while t <= duration:
			var p: Vector3 = position_at(i, origin, t)
			lines.append(prev)
			lines.append(p)
			prev = p
			t += step


## 读取敌机场景里某个属性的值：场景里改过就用场景的，否则用脚本默认值。
func _enemy_default(prop: StringName, fallback: Variant) -> Variant:
	if enemy_scene == null:
		return fallback
	var state: SceneState = enemy_scene.get_state()
	var script: Script = null
	for k: int in state.get_node_property_count(0):
		var n: StringName = state.get_node_property_name(0, k)
		if n == prop:
			return state.get_node_property_value(0, k)
		if n == &"script":
			script = state.get_node_property_value(0, k)
	if script:
		var v: Variant = script.get_property_default_value(prop)
		if v != null:
			return v
	return fallback
