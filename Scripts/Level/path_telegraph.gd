class_name PathTelegraph
extends MeshInstance3D
## 攻击前摇特效（类似 MMO 的技能预警）：沿敌机即将飞过的轨迹铺一条半透明的带子，
## 两侧描边，再从起点往终点逐渐填满。填满的那一刻敌机出发，之后特效淡出。
## 由 EnemyFormation 在生成横向编队时自动创建。

## 填充时长（秒）= 敌机出发前的预警时间。
var duration: float = 1.5
## 填满后淡出用的时间（秒）。
var fade_time: float = 0.4
## 带子宽度（米）。
var width: float = 1.2
## 描边粗细（米）。
var edge_thickness: float = 0.1
## 颜色。
var color: Color = Color(1.0, 0.4, 0.3)
## 各部分不透明度：底色 / 已填充部分 / 描边 / 快填满时的闪烁幅度。
var base_alpha: float = 0.04
var fill_alpha: float = 0.12
var edge_alpha: float = 0.35
var flash_alpha: float = 0.08

## 生成后先等多久才开始显示（秒）。
var start_delay: float = 0.0

var _paths: Array[PackedVector3Array] = []
var _lengths: Array[PackedFloat32Array] = []   # 每条轨迹上每个点到起点的累计长度
var _time: float = 0.0
var _im: ImmediateMesh


## paths：每条轨迹的点（世界坐标，按飞行顺序）。
func setup(paths: Array[PackedVector3Array], show_time: float, band_width: float) -> void:
	duration = show_time
	width = band_width
	for p: PackedVector3Array in paths:
		if p.size() < 2:
			continue
		_paths.append(p)
		var acc: PackedFloat32Array = PackedFloat32Array([0.0])
		for k: int in range(1, p.size()):
			acc.append(acc[k - 1] + p[k].distance_to(p[k - 1]))
		_lengths.append(acc)

	_im = ImmediateMesh.new()
	mesh = _im
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rebuild()


func _process(delta: float) -> void:
	if start_delay > 0.0:
		start_delay -= delta
		visible = start_delay <= 0.0
		if start_delay > 0.0:
			return
	_time += delta
	if _time >= duration + fade_time:
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	if _paths.is_empty():
		return
	# progress：填充进度 0~1；fade：整体透明度（填满后逐渐变 0）
	var progress: float = clampf(_time / maxf(duration, 0.01), 0.0, 1.0)
	var fade: float = 1.0 - clampf((_time - duration) / maxf(fade_time, 0.01), 0.0, 1.0)
	# 快填满时闪烁，提示"要来了"
	var flash: float = 0.0
	if progress > 0.8 and progress < 1.0:
		flash = flash_alpha * (0.5 + 0.5 * cos(_time * TAU * 8.0))

	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in _paths.size():
		var path: PackedVector3Array = _paths[i]
		var acc: PackedFloat32Array = _lengths[i]
		var total: float = acc[acc.size() - 1]
		# 底色：整条轨迹
		_ribbon(path, acc, total, 0.0, width, _col(base_alpha * fade))
		# 填充：从起点到当前进度
		_ribbon(path, acc, total * progress, 0.0, width, _col((fill_alpha + flash) * fade))
		# 两侧描边
		var edge_off: float = (width - edge_thickness) * 0.5
		_ribbon(path, acc, total, edge_off, edge_thickness, _col(edge_alpha * fade))
		_ribbon(path, acc, total, -edge_off, edge_thickness, _col(edge_alpha * fade))
	_im.surface_end()


func _col(alpha: float) -> Color:
	var c: Color = color
	c.a = alpha
	return c


## 沿轨迹从起点画到累计长度 s_end 处的一条带子，带子中心偏离轨迹 offset 米，宽 w 米。
func _ribbon(path: PackedVector3Array, acc: PackedFloat32Array, s_end: float,
		offset: float, w: float, c: Color) -> void:
	if s_end < 0.01 or c.a <= 0.001:
		return
	var prev_l: Vector3 = Vector3.ZERO
	var prev_r: Vector3 = Vector3.ZERO
	for k: int in path.size():
		var p: Vector3 = path[k]
		var past_end: bool = acc[k] > s_end
		if past_end:
			# 最后一段只画到 s_end 为止
			var t: float = (s_end - acc[k - 1]) / maxf(acc[k] - acc[k - 1], 0.0001)
			p = path[k - 1].lerp(path[k], t)
		var side: Vector3 = _side_at(path, k)
		var l: Vector3 = p + side * (offset + w * 0.5)
		var r: Vector3 = p + side * (offset - w * 0.5)
		if k > 0:
			_quad(prev_l, prev_r, l, r, c)
		prev_l = l
		prev_r = r
		if past_end:
			break


## 第 k 个点处垂直于轨迹、且在画面平面内的方向。
func _side_at(path: PackedVector3Array, k: int) -> Vector3:
	var a: Vector3 = path[maxi(k - 1, 0)]
	var b: Vector3 = path[mini(k + 1, path.size() - 1)]
	var tangent: Vector3 = b - a
	tangent.z = 0.0
	if tangent.length() < 0.0001:
		return Vector3.UP
	return Vector3.BACK.cross(tangent.normalized())


func _quad(l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, c: Color) -> void:
	for v: Vector3 in [l0, r0, r1, l0, r1, l1]:
		_im.surface_set_color(c)
		_im.surface_add_vertex(v)
