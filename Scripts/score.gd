extends Node
## 分数系统（Autoload 名：Score）。所有关卡自动生效，不用摆节点。
## 分数来源：
## - 存活：每秒 survive_per_second 分（乘连击倍率）。
## - 擦边：从障碍旁边擦过去，基础 graze_base 分，越贴近越多（最多 × graze_close_bonus），再乘连击倍率。
## 连击：每次擦边倍率 + combo_step（上限 combo_max）；combo_timeout 秒内没有新的擦边，倍率回到 1。
## 撞毁 / 离开画面判负后停止计分；按 R 重来清零。最高分存到 user://highscore.cfg。

@export_group("存活")
@export var survive_per_second: float = 10.0

@export_group("擦边")
## 一次擦边的基础分。
@export var graze_base: float = 100.0
## 贴着飞过（closeness = 1）时的额外倍数：分数 = 基础 × lerp(1, 这个值, closeness)。
@export var graze_close_bonus: float = 3.0

@export_group("连击")
@export var combo_step: float = 0.5
@export var combo_max: float = 5.0
## 多久没有擦边，连击就断（秒）。
@export var combo_timeout: float = 3.0

## 当前分数（带小数，显示时取整）。
var score: float = 0.0
## 当前连击倍率（1 = 没有连击）。
var combo: float = 1.0
## 本局擦边次数。
var graze_count: int = 0
## 最高分。
var high_score: int = 0
## 是否正在计分（判负后停止）。
var running: bool = true

const SAVE_PATH = "user://highscore.cfg"

var _combo_left: float = 0.0
var _layer: CanvasLayer
var _score_label: Label
var _combo_label: Label
var _result_label: Label


func _ready() -> void:
	_load_high_score()
	_build_hud()
	var bus: Node = get_node(^"/root/SignalBus")
	bus.connect(&"player_grazed", _on_grazed)
	bus.connect(&"player_respawned", reset)
	bus.connect(&"player_failed", _on_failed)
	bus.connect(&"level_finished", _on_level_finished)
	# 切换场景时清零
	get_tree().scene_changed.connect(reset)
	reset()


## 清零，重新开始计分。
func reset() -> void:
	score = 0.0
	combo = 1.0
	graze_count = 0
	_combo_left = 0.0
	running = true
	_result_label.visible = false
	_emit()


func _process(delta: float) -> void:
	# 没有玩家飞机的场景（菜单等）不计分、不显示
	var has_player: bool = get_tree().get_first_node_in_group(&"player") != null
	_layer.visible = has_player
	if not running or not has_player:
		return
	score += survive_per_second * combo * delta
	if _combo_left > 0.0:
		_combo_left -= delta
		if _combo_left <= 0.0:
			combo = 1.0
	_emit()


func _on_grazed(obstacle: Node3D, _distance: float, closeness: float) -> void:
	if not running:
		return
	graze_count += 1
	var gained: float = graze_base * lerpf(1.0, graze_close_bonus, closeness) * combo
	score += gained
	combo = minf(combo + combo_step, combo_max)
	_combo_left = combo_timeout
	_emit()
	_popup(obstacle, "%d" % roundi(gained), closeness)


func _on_failed(_reason: String) -> void:
	_finish("撞毁了")


func _on_level_finished(_level: Resource) -> void:
	_finish("通关！")


func _finish(title: String) -> void:
	if not running:
		return
	running = false
	combo = 1.0
	var final_score: int = roundi(score)
	var new_record: bool = final_score > high_score
	if new_record:
		high_score = final_score
		_save_high_score()
	_result_label.text = "%s\n分数 %d   擦边 %d 次\n%s\n按 R 重来" % [
			title, final_score, graze_count,
			"新纪录！" if new_record else "最高分 %d" % high_score]
	_result_label.visible = true
	_emit()
	

func _emit() -> void:
	_score_label.text = "分数 %d\n最高 %d" % [roundi(score), max(high_score, roundi(score))]
	if combo > 1.0:
		_combo_label.text = "连击 ×%.1f" % combo
		# 快断的时候变暗提示
		_combo_label.modulate.a = 0.4 + 0.6 * clampf(_combo_left / combo_timeout, 0.0, 1.0)
		_combo_label.visible = true
	else:
		_combo_label.visible = false
	get_node(^"/root/SignalBus").emit_signal(&"score_changed", roundi(score), combo)


# ———————————— 显示 ————————————

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20  # 在像素滤镜（layer 10）之上
	add_child(_layer)
	_score_label = _make_label(28, HORIZONTAL_ALIGNMENT_RIGHT)
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_score_label.offset_left = -360
	_score_label.offset_right = -24
	_score_label.offset_top = 16
	_combo_label = _make_label(32, HORIZONTAL_ALIGNMENT_RIGHT)
	_combo_label.add_theme_color_override(&"font_color", Color(1, 0.85, 0.2))
	_combo_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_combo_label.offset_left = -360
	_combo_label.offset_right = -24
	_combo_label.offset_top = 96
	_result_label = _make_label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_label.visible = false


func _make_label(size: int, align: HorizontalAlignment) -> Label:
	var l: Label = Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(l)
	return l


## 在擦边的位置飘一个分数，往上飘并淡出。越险越大、越黄。
func _popup(obstacle: Node3D, text: String, closeness: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(obstacle) or cam.is_position_behind(obstacle.global_position):
		return
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	# 飘字放在玩家和障碍之间，靠近玩家，玩家一眼就能看到
	var at: Vector3 = obstacle.global_position
	if player:
		at = player.global_position.lerp(obstacle.global_position, 0.3)
	var l: Label = _make_label(roundi(lerpf(22.0, 34.0, closeness)), HORIZONTAL_ALIGNMENT_CENTER)
	l.text = text
	l.add_theme_color_override(&"font_color", Color.WHITE.lerp(Color(1, 0.85, 0.2), closeness))
	l.position = cam.unproject_position(at) - Vector2(80, 20)
	l.size = Vector2(160, 40)
	var tw: Tween = l.create_tween().set_parallel(true)
	tw.tween_property(l, ^"position:y", l.position.y - 60.0, 0.8)
	tw.tween_property(l, ^"modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ———————————— 最高分存档 ————————————

func _load_high_score() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("score", "high", 0))


func _save_high_score() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("score", "high", high_score)
	cfg.save(SAVE_PATH)
