class_name EnemyPlane
extends AnimatableBody3D
## 敌机（障碍物）基类。两样东西可以替换，组合出不同的敌机：
## - 建模：model_scene（留空 = 用场景里的红色占位模型）
## - 飞行轨迹：movement（EnemyMovement 资源，如 MoveLinear / MoveSine）
## 做新敌机：在文件系统里右键 enemy_plane.tscn →「新建继承场景」，改这两项、调碰撞形状即可。
## 玩家不会被它物理推开，撞上时由 ContactArea 判定，玩家扣一条命。

## 替换用的建模场景。
@export var model_scene: PackedScene
## 飞行轨迹。留空 = 原地不动。
@export var movement: EnemyMovement
## 撞到玩家时给玩家造成的伤害。
@export var contact_damage: int = 1
## 飞到这个 Z 之后（已经飞过镜头）自动销毁。
@export var despawn_z: float = 30.0
## 最长存活时间（秒），0 = 不限制。
@export var lifetime: float = 0.0

@onready var _model_root: Node3D = $Model
@onready var _contact_area: Area3D = $ContactArea

var _origin: Vector3
var _time: float = 0.0


func _ready() -> void:
	_origin = global_position
	if model_scene:
		for child in _model_root.get_children():
			child.queue_free()
		_model_root.add_child(model_scene.instantiate())
	_contact_area.body_entered.connect(_on_contact)


func _physics_process(delta: float) -> void:
	_time += delta
	if movement:
		global_position = _origin + movement.get_offset(_time)

	if global_position.z > despawn_z or (lifetime > 0.0 and _time >= lifetime):
		queue_free()


## 找到玩家飞机（plane.tscn 根节点在 "player" 组里）。
func get_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _on_contact(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("take_hit"):
		body.call("take_hit", contact_damage)
