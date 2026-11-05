@tool
class_name PathPreview
extends RefCounted
## 编辑器里画敌机轨迹用的小工具：把线段画进一个不保存到场景的 MeshInstance3D。


## 取得（或创建）owner 下用于预览的 MeshInstance3D。它是内部子节点，不会存进 .tscn。
static func get_or_create(owner_node: Node3D) -> MeshInstance3D:
	var mi: MeshInstance3D = owner_node.get_node_or_null(^"_PathPreview") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "_PathPreview"
		mi.mesh = ImmediateMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		mi.material_override = mat
		owner_node.add_child(mi, false, Node.INTERNAL_MODE_BACK)
	# 预览线用世界坐标画，所以不跟随父节点变换
	mi.top_level = true
	mi.global_transform = Transform3D.IDENTITY
	return mi


## 清空并开始绘制。
static func begin(mi: MeshInstance3D) -> ImmediateMesh:
	var im: ImmediateMesh = mi.mesh as ImmediateMesh
	im.clear_surfaces()
	return im


## 画一组线段（lines 两两一对），颜色 color。
static func draw_lines(im: ImmediateMesh, lines: PackedVector3Array, color: Color) -> void:
	if lines.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(color)
	for p: Vector3 in lines:
		im.surface_add_vertex(p)
	im.surface_end()


## 在 p 处画一个小十字，标出出发点。
static func draw_cross(im: ImmediateMesh, p: Vector3, size: float, color: Color) -> void:
	var lines: PackedVector3Array = PackedVector3Array([
		p - Vector3.RIGHT * size, p + Vector3.RIGHT * size,
		p - Vector3.UP * size, p + Vector3.UP * size,
		p - Vector3.BACK * size, p + Vector3.BACK * size,
	])
	draw_lines(im, lines, color)


## 移除预览。
static func clear(owner_node: Node3D) -> void:
	var mi: MeshInstance3D = owner_node.get_node_or_null(^"_PathPreview") as MeshInstance3D
	if mi:
		(mi.mesh as ImmediateMesh).clear_surfaces()
