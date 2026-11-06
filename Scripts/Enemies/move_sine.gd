class_name MoveSine
extends EnemyMovement
## 沿 velocity 直线前进，同时沿 sway_axis 方向做正弦摆动（蛇形）。

## 前进速度（米/秒）。默认沿 +Z 朝玩家飞来。
@export var velocity: Vector3 = Vector3(0, 0, 8)
## 摆动方向。(1,0,0) = 左右摆，(0,1,0) = 上下摆。
@export var sway_axis: Vector3 = Vector3(1, 0, 0)
## 摆动幅度（米）。
@export var amplitude: float = 4.0
## 每秒摆动几个来回。
@export var frequency: float = 0.4


func get_offset(t: float) -> Vector3:
	return velocity * t + sway_axis.normalized() * sin(t * TAU * frequency) * amplitude
