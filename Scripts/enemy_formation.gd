@tool
class_name EnemyFormation
extends Node3D
## 敌机编队生成器：按 data（FormationData）生成一整队敌机。
## 节点自身的位置 = 阵型中心的出发点。
## - 直接摆进场景用：设置 data，勾 spawn_on_ready。
## - 关卡里用：LevelRunner 会自动创建它，不需要手动摆。
## 编辑器里会画出每架敌机的飞行路线（preview_paths）。
## 整队消失时发 SignalBus.formation_finished(formation, killed, total)。

## 编队数据（可以新建内嵌的，也可以拖一个 .tres 进来复用）。
@export var data: FormationData

@export_group("启动")
## 进入场景后自动生成。关掉则需要手动调用 spawn()。
@export var spawn_on_ready: bool = true
## 自动生成前等待（秒）。
@export var initial_delay: float = 0.0

@export_group("编辑器预览")
## 在编辑器里画出飞行路线。
@export var preview_paths: bool = true
## 预览多少秒的路线。
@export var preview_duration: float = 12.0
@export var preview_color: Color = Color(1, 0.4, 0.2)

## 本队总架数 / 已消失架数 / 被打爆架数。
var total: int = 0
var gone: int = 0
var killed: int = 0
## 是否已经整队结束。
var finished: bool = false

var _preview_timer: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(false)
	if spawn_on_ready:
		if initial_delay > 0.0:
			await get_tree().create_timer(initial_delay).timeout
		spawn()


func _process(delta: float) -> void:
	# 只在编辑器里跑：定时重画预览（改参数后很快就能看到新路线）
	if not Engine.is_editor_hint():
		return
	_preview_timer -= delta
	if _preview_timer > 0.0:
		return
	_preview_timer = 0.2
	if preview_paths and data:
		var mi: MeshInstance3D = PathPreview.get_or_create(self)
		var im: ImmediateMesh = PathPreview.begin(mi)
		var lines: PackedVector3Array = PackedVector3Array()
		data.append_preview_lines(lines, global_position, preview_duration)
		PathPreview.draw_lines(im, lines, preview_color)
		for i: int in data.count:
			PathPreview.draw_cross(im, data.position_at(i, global_position, 0.0), 0.6, Color.WHITE)
	else:
		PathPreview.clear(self)


## 按阵型生成一整队敌机。
func spawn() -> void:
	if data == null or data.enemy_scene == null:
		push_warning("%s：没有设置编队数据或敌机场景" % name)
		_finish()
		return
	total = data.count
	gone = 0
	killed = 0
	finished = false
	for i: int in data.count:
		var enemy: Node3D = data.create_enemy(i, global_position)
		enemy.name = "%s_%d" % [name, i]
		enemy.set("on_removed", _on_enemy_removed)
		# 加到编队的父节点下，这样编队节点本身被删也不影响已出发的敌机
		get_parent().add_child(enemy)


func _on_enemy_removed(was_killed: bool) -> void:
	gone += 1
	if was_killed:
		killed += 1
	if gone >= total:
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	# @tool 脚本里不直接写 SignalBus 标识符，避免编辑器没刷新 Autoload 时整个脚本编译失败
	get_node(^"/root/SignalBus").emit_signal(&"formation_finished", self, killed, total)
