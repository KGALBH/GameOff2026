@tool
class_name LevelCsv
extends RefCounted
## 从 CSV 表格读取关卡（用 Excel / WPS / Google 表格编辑，一行 = 一波）。
## 第一行是表头，列的顺序随意，不认识的列会被忽略；空着的格子用默认值。
## 以 # 开头的行是注释；整行为空的行跳过。
##
## 列（中文或英文表头都行）：
##   备注 note        随便写，只给人看
##   触发 trigger     时间 / 接上一波（默认 时间）
##   时间 time        触发=时间：关卡第几秒出发；触发=接上一波：上一波清完后等几秒
##   敌机 enemy       留空 = 默认敌机；可以写 res:// 路径，或 Scenes/Enemies 里的场景名（不带 .tscn）
##   数量 count       默认 5
##   阵型 shape       横排 / V字 / 方阵 / 环形 / 纵队（默认 横排）
##   间距 spacing     米，默认 3
##   每行 columns     方阵每行几架，默认 3
##   出发间隔 stagger 每架之间隔几秒出发（纵队靠它拉开），默认 0
##   相位差 phase     每架之间的摆动错位（0~1），默认 0
##   方向 direction   深处 / 左 / 右 / 上 / 下（= 从哪边飞进来），或者三个数字 "1 0 0"；默认 深处
##   X Y Z            出发点。留空时按方向给默认值：深处 z=-160，左 x=-32，右 x=32，上 y=20，下 y=-20
##   速度 speed       米/秒
##   轨迹 pattern     直线 / 蛇形 / 之字 / 螺旋
##   幅度 amplitude   摆动幅度（米）
##   频率 frequency   每秒摆几个来回
##   预警 warning     是 / 否：横飞编队出发前是否显示预警（默认 是）
## 方向、速度、轨迹、幅度、频率任填一个就会覆盖敌机场景里的轨迹设置，没填的用敌机场景的值。
##
## 注意：Excel 保存时请选「CSV UTF-8（逗号分隔）」，否则中文会乱码。

const DEFAULT_ENEMY = "res://Scenes/enemy.tscn"

const HEADER_ALIASES = {
	"备注": "note", "note": "note",
	"触发": "trigger", "trigger": "trigger",
	"时间": "time", "time": "time",
	"敌机": "enemy", "enemy": "enemy",
	"数量": "count", "count": "count",
	"阵型": "shape", "shape": "shape",
	"间距": "spacing", "spacing": "spacing",
	"每行": "columns", "columns": "columns",
	"出发间隔": "stagger", "stagger": "stagger",
	"相位差": "phase", "phase": "phase",
	"方向": "direction", "direction": "direction",
	"x": "x", "y": "y", "z": "z",
	"速度": "speed", "speed": "speed",
	"轨迹": "pattern", "pattern": "pattern",
	"幅度": "amplitude", "amplitude": "amplitude",
	"频率": "frequency", "frequency": "frequency",
	"预警": "warning", "warning": "warning",
}

const SHAPES = {
	"横排": FormationData.Shape.LINE, "line": FormationData.Shape.LINE,
	"v字": FormationData.Shape.V, "v": FormationData.Shape.V, "人字": FormationData.Shape.V,
	"方阵": FormationData.Shape.GRID, "grid": FormationData.Shape.GRID,
	"环形": FormationData.Shape.CIRCLE, "circle": FormationData.Shape.CIRCLE,
	"纵队": FormationData.Shape.TRAIL, "trail": FormationData.Shape.TRAIL,
}

const PATTERNS = {
	"直线": EnemyPath.Pattern.STRAIGHT, "straight": EnemyPath.Pattern.STRAIGHT,
	"蛇形": EnemyPath.Pattern.SINE, "sine": EnemyPath.Pattern.SINE,
	"之字": EnemyPath.Pattern.ZIGZAG, "zigzag": EnemyPath.Pattern.ZIGZAG,
	"螺旋": EnemyPath.Pattern.CIRCLE, "画圈": EnemyPath.Pattern.CIRCLE, "spiral": EnemyPath.Pattern.CIRCLE,
}

## 方向关键字 → [前进方向, 默认出发点]
const DIRECTIONS = {
	"深处": [Vector3(0, 0, 1), Vector3(0, 0, -70)], "deep": [Vector3(0, 0, 1), Vector3(0, 0, -70)],
	"左": [Vector3(1, 0, 0), Vector3(-32, 0, 0)], "left": [Vector3(1, 0, 0), Vector3(-32, 0, 0)],
	"右": [Vector3(-1, 0, 0), Vector3(32, 0, 0)], "right": [Vector3(-1, 0, 0), Vector3(32, 0, 0)],
	"上": [Vector3(0, -1, 0), Vector3(0, 20, 0)], "top": [Vector3(0, -1, 0), Vector3(0, 20, 0)],
	"下": [Vector3(0, 1, 0), Vector3(0, -20, 0)], "bottom": [Vector3(0, 1, 0), Vector3(0, -20, 0)],
}


## 读取 CSV 并生成 LevelData。出错的行会跳过并打印警告。
static func load_level(path: String) -> LevelData:
	var raw: String = path
	path = resolve_path(path)
	if path == "":
		push_error("关卡表格的 uid 找不到：%s（在 LevelRunner 上重新选一次表格文件）" % raw)
		return null
	_ensure_kept_as_file(path)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("关卡表格读不到或是空的：%s" % path)
		return null
	# 去掉 UTF-8 BOM（Excel 的「CSV UTF-8」会带）
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3)
	var text: String = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		push_error("关卡表格不是 UTF-8 编码（中文会乱码）：%s\n请在 Excel 里「另存为」→ 选「CSV UTF-8（逗号分隔）」。" % path)
		return null

	var level: LevelData = LevelData.new()
	level.level_name = path.get_file().get_basename()
	var rows: Array[PackedStringArray] = _parse_csv(text)
	var header: PackedStringArray = PackedStringArray()
	for r: int in rows.size():
		var row: PackedStringArray = rows[r]
		if _is_blank(row) or row[0].strip_edges().begins_with("#"):
			continue
		if header.is_empty():
			header = row
			continue
		var cells: Dictionary = {}
		for c: int in mini(row.size(), header.size()):
			var key: String = HEADER_ALIASES.get(header[c].strip_edges().to_lower(), "")
			if key != "":
				cells[key] = row[c].strip_edges()
		var wave: WaveEntry = _make_wave(cells, path, r + 1)
		if wave:
			level.waves.append(wave)
	return level


## 检查器里选文件可能存成 uid://，FileAccess 读不了，换成 res:// 路径。找不到返回 ""。
static func resolve_path(path: String) -> String:
	if not path.begins_with("uid://"):
		return path
	var id: int = ResourceUID.text_to_id(path)
	return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""


## Godot 默认把 .csv 当成"翻译表"导入，关卡表格会导入失败（报 Cannot open TextFile）。
## 在编辑器里发现是这种情况，就自动把它改成「保留文件」导入（保留原来的 uid）。
static func _ensure_kept_as_file(path: String) -> void:
	if not Engine.is_editor_hint():
		return
	var import_path: String = path + ".import"
	var text: String = FileAccess.get_file_as_string(import_path)
	if text == "" or text.contains("importer=\"keep\""):
		return
	var uid_line: String = ""
	for line: String in text.split("\n"):
		if line.begins_with("uid="):
			uid_line = line + "\n"
	var f: FileAccess = FileAccess.open(import_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("[remap]\n\nimporter=\"keep\"\n" + uid_line)
	f.close()
	var editor: Object = Engine.get_singleton(&"EditorInterface")
	if editor:
		editor.call(&"get_resource_filesystem").call(&"reimport_files", PackedStringArray([path]))
	print("关卡表格 %s 原来被当成翻译表导入，已自动改成「保留文件」。" % path.get_file())


static func _make_wave(cells: Dictionary, path: String, line: int) -> WaveEntry:
	var where: String = "%s 第 %d 行" % [path.get_file(), line]
	var w: WaveEntry = WaveEntry.new()
	var f: FormationData = FormationData.new()
	w.formation = f
	w.note = cells.get("note", "")

	var trig: String = String(cells.get("trigger", "")).to_lower()
	w.trigger = WaveEntry.Trigger.AFTER_PREVIOUS if trig in ["接上一波", "上一波后", "after", "after_previous"] else WaveEntry.Trigger.AT_TIME
	w.time = _num(cells, "time", 0.0, where)

	var enemy_name: String = cells.get("enemy", "")
	var scene: PackedScene = _find_enemy(enemy_name)
	if scene == null:
		push_warning("%s：找不到敌机「%s」，用默认敌机" % [where, enemy_name])
		scene = load(DEFAULT_ENEMY)
	f.enemy_scene = scene

	f.count = maxi(1, int(_num(cells, "count", 5, where)))
	f.shape = _lookup(SHAPES, cells.get("shape", ""), FormationData.Shape.LINE, "阵型", where) as FormationData.Shape
	f.spacing = _num(cells, "spacing", 3.0, where)
	f.grid_columns = maxi(1, int(_num(cells, "columns", 3, where)))
	f.stagger = _num(cells, "stagger", 0.0, where)
	f.phase_step = _num(cells, "phase", 0.0, where)
	var warn: String = String(cells.get("warning", "")).to_lower()
	f.lateral_warning = not (warn in ["否", "不", "no", "false", "0"])

	# 方向 + 默认出发点
	var dir_text: String = String(cells.get("direction", "")).to_lower()
	var dir: Vector3 = Vector3(0, 0, 1)
	var default_pos: Vector3 = Vector3(0, 0, -160)
	if DIRECTIONS.has(dir_text):
		dir = DIRECTIONS[dir_text][0]
		default_pos = DIRECTIONS[dir_text][1]
	elif dir_text != "":
		var parts: PackedFloat64Array = dir_text.replace(";", " ").split_floats(" ", false)
		if parts.size() == 3:
			dir = Vector3(parts[0], parts[1], parts[2])
			default_pos = Vector3.ZERO
		else:
			push_warning("%s：看不懂方向「%s」，按 深处 处理" % [where, dir_text])
	w.position = Vector3(
			_num(cells, "x", default_pos.x, where),
			_num(cells, "y", default_pos.y, where),
			_num(cells, "z", default_pos.z, where))

	# 轨迹：任填一项就覆盖，没填的沿用敌机场景里的值
	var keys: Array[String] = ["direction", "speed", "pattern", "amplitude", "frequency"]
	if keys.any(func(k: String) -> bool: return String(cells.get(k, "")) != ""):
		f.override_movement = true
		f.direction = dir
		f.speed = _num(cells, "speed", f._enemy_default(&"speed", 15.0), where)
		f.pattern = _lookup(PATTERNS, cells.get("pattern", ""), f._enemy_default(&"pattern", 0), "轨迹", where) as EnemyPath.Pattern
		f.amplitude = _num(cells, "amplitude", f._enemy_default(&"amplitude", 4.0), where)
		f.frequency = _num(cells, "frequency", f._enemy_default(&"frequency", 0.5), where)
	return w


static func _find_enemy(name: String) -> PackedScene:
	if name == "":
		return load(DEFAULT_ENEMY)
	var candidates: Array[String] = [name, "res://Scenes/Enemies/%s.tscn" % name, "res://Scenes/%s.tscn" % name]
	for p: String in candidates:
		if p.begins_with("res://") and ResourceLoader.exists(p):
			return load(p) as PackedScene
	return null


static func _num(cells: Dictionary, key: String, fallback: float, where: String) -> float:
	var s: String = cells.get(key, "")
	if s == "":
		return fallback
	if not s.is_valid_float():
		push_warning("%s：「%s」不是数字（%s），用默认值 %s" % [where, s, key, fallback])
		return fallback
	return s.to_float()


static func _lookup(table: Dictionary, value: String, fallback: int, what: String, where: String) -> int:
	var v: String = value.strip_edges().to_lower()
	if v == "":
		return fallback
	if table.has(v):
		return table[v]
	push_warning("%s：看不懂%s「%s」，用默认值" % [where, what, value])
	return fallback


static func _is_blank(row: PackedStringArray) -> bool:
	for c: String in row:
		if c.strip_edges() != "":
			return false
	return true


## 简单的 CSV 解析：支持双引号包起来的格子（里面可以有逗号、换行，"" 表示一个引号）。
static func _parse_csv(text: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var row: PackedStringArray = PackedStringArray()
	var cell: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < text.length():
		var ch: String = text[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < text.length() and text[i + 1] == "\"":
					cell += "\""
					i += 1
				else:
					in_quotes = false
			else:
				cell += ch
		elif ch == "\"":
			in_quotes = true
		elif ch == ",":
			row.append(cell)
			cell = ""
		elif ch == "\n" or ch == "\r":
			if ch == "\r" and i + 1 < text.length() and text[i + 1] == "\n":
				i += 1
			row.append(cell)
			rows.append(row)
			row = PackedStringArray()
			cell = ""
		else:
			cell += ch
		i += 1
	if cell != "" or not row.is_empty():
		row.append(cell)
		rows.append(row)
	return rows
