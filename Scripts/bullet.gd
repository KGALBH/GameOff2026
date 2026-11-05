class_name Bullet
extends Area3D
## 直线飞行的子弹：沿自身 -Z（前方）匀速飞行，撞到物体或超过寿命后消失。

## 飞行速度（米/秒）。
@export var speed: float = 60.0
## 存活时间（秒），超时自动销毁。
@export var lifetime: float = 3.0
## 打中敌机造成的伤害。
@export var damage: int = 1

## 发射者（不会打到自己）。
var shooter: Node = null
## 自定义飞行速度（世界坐标）。为零时按 speed 沿自身前方飞。
var velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	# 放在第一帧再算：发射者是在 add_child 之后才设置朝向的
	if velocity == Vector3.ZERO:
		velocity = -global_basis.z * speed
	global_position += velocity * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


## 打中敌机：扣血并销毁子弹。
func _on_area_entered(area: Area3D) -> void:
	if area is Enemy:
		(area as Enemy).take_damage(damage)
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	queue_free()
