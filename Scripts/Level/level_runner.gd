@tool
class_name LevelRunner
extends Node3D
## 关卡播放器：读取 LevelData 时间表，到点生成编队。
## 用法：在关卡场景里加一个 LevelRunner（放在世界原点），把 level 设成一个 LevelData.tres。
## 编辑器里会画出所有波次的飞行路线；拖动 preview_time 可以看到"第 N 秒时敌机在哪"。

@export var level: LevelData

@export_group("运行")
## 进入场景后自动开始。关掉则需要手动调用 start()。
@export var autostart: bool = true
## 调试用：从第几秒开始跑（跳过之前按时间触发的波次）。正式关卡设回 0。
@export var debug_start_time: float = 0.0

@export_group("编辑器预览")
## 在编辑器里画出所有波次的飞行路线。
@export var preview_paths: bool = true
## 只预览某一波（-1 = 全部）。
@export var preview_only_wave: int = -1
## 每条路线预览多少秒。
@export var preview_duration: float = 12.0
## 拖动这个看关卡第 N 秒时敌机的位置（只对 AT_TIME 波次有效，黄点表示）。
@export var preview_time: float = 0.0

enum _State { PENDING, ACTIVE, DONE }

var elapsed: float = 0.0
var running: bool = false

var _states: Array[_State] = []
var _done_time: Array[float] = []
var _formations: Dictionary = {}   # EnemyFormation -> 波次序号
var _finished_emitted: bool = false
var _all_done_time: float = -1.0
var _preview_timer: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_bus().connect(&"formation_finished", _on_formation_finished)
	if autostart:
		start()


## 开始（或重新开始）播放关卡。
func start() -> void:
	if level == null:
		push_warning("LevelRunner：没有设置 level")
		return
	elapsed = debug_start_time
	running = true
	_finished_emitted = false
	_all_done_time = -1.0
	_states.clear()
	_done_time.clear()
	for w: WaveEntry in level.waves:
		var skipped: bool = debug_start_time > 0.0 and w and w.trigger == WaveEntry.Trigger.AT_TIME and w.time < debug_start_time
		_states.append(_State.DONE if skipped else _State.PENDING)
		# 被跳过的波次算作"开局前就结束了"，后面接着它的 AFTER_PREVIOUS 波次会马上出发
		_done_time.append(-INF if skipped else 0.0)
	_bus().emit_signal(&"level_started", level)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_preview(delta)
		return
	if not running:
		return
	elapsed += delta

	for i: int in _states.size():
		if _states[i] != _State.PENDING:
			continue
		var t: float = _ready_time(i)
		if t != INF and elapsed >= t:
			_spawn_wave(i)

	# 全部结束 → 等 end_delay → 通关
	if not _finished_emitted and _states.all(func(s: _State) -> bool: return s == _State.DONE):
		if _all_done_time < 0.0:
			_all_done_time = elapsed
		if elapsed - _all_done_time >= level.end_delay:
			_finished_emitted = true
			running = false
			_bus().emit_signal(&"level_finished", level)


## 第 i 波应该在关卡第几秒出发；还不能确定（上一波没结束）时返回 INF。
func _ready_time(i: int) -> float:
	var w: WaveEntry = level.waves[i]
	if w == null:
		return 0.0
	if w.trigger == WaveEntry.Trigger.AT_TIME or i == 0:
		return w.time
	if _states[i - 1] != _State.DONE:
		return INF
	return _done_time[i - 1] + w.time


func _spawn_wave(i: int) -> void:
	var w: WaveEntry = level.waves[i]
	if w == null or w.formation == null:
		_mark_done(i)
		return
	_states[i] = _State.ACTIVE
	var f: EnemyFormation = EnemyFormation.new()
	f.name = "Wave%d" % i
	f.data = w.formation
	f.spawn_on_ready = false
	f.preview_paths = false
	_formations[f] = i
	add_child(f)
	f.global_position = w.position
	_bus().emit_signal(&"wave_started", level, i)
	f.spawn()


func _on_formation_finished(formation: Node3D, _killed: int, _total: int) -> void:
	if not _formations.has(formation):
		return
	var i: int = _formations[formation]
	_formations.erase(formation)
	formation.queue_free()
	_mark_done(i)


## 取 SignalBus。@tool 脚本里不直接写 SignalBus 标识符，避免编辑器没刷新 Autoload 时整个脚本编译失败。
func _bus() -> Node:
	return get_node(^"/root/SignalBus")


func _mark_done(i: int) -> void:
	_states[i] = _State.DONE
	_done_time[i] = elapsed


# ———————————— 编辑器预览 ————————————

func _editor_preview(delta: float) -> void:
	_preview_timer -= delta
	if _preview_timer > 0.0:
		return
	_preview_timer = 0.2
	if not preview_paths or level == null:
		PathPreview.clear(self)
		return
	var mi: MeshInstance3D = PathPreview.get_or_create(self)
	var im: ImmediateMesh = PathPreview.begin(mi)
	for i: int in level.waves.size():
		if preview_only_wave >= 0 and i != preview_only_wave:
			continue
		var w: WaveEntry = level.waves[i]
		if w == null or w.formation == null:
			continue
		# 每一波一个颜色
		var color: Color = Color.from_hsv(fmod(i * 0.17, 1.0), 0.8, 1.0)
		var lines: PackedVector3Array = PackedVector3Array()
		w.formation.append_preview_lines(lines, w.position, preview_duration)
		PathPreview.draw_lines(im, lines, color)
		for k: int in w.formation.count:
			PathPreview.draw_cross(im, w.formation.position_at(k, w.position, 0.0), 0.6, color.lightened(0.5))
		# 时间刷：AT_TIME 波次在 preview_time 时的位置
		if w.trigger == WaveEntry.Trigger.AT_TIME and preview_time >= w.time:
			for k: int in w.formation.count:
				var p: Vector3 = w.formation.position_at(k, w.position, preview_time - w.time)
				PathPreview.draw_cross(im, p, 1.2, Color.YELLOW)
