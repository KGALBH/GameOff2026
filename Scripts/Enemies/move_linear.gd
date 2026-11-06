class_name MoveLinear
extends EnemyMovement
## 直线匀速飞行。

## 飞行速度（米/秒）。默认沿 +Z 朝玩家飞来。
@export var velocity: Vector3 = Vector3(0, 0, 8)


func get_offset(t: float) -> Vector3:
	return velocity * t
