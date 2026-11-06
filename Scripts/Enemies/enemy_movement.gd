class_name EnemyMovement
extends Resource
## 敌机飞行轨迹基类。新轨迹：继承它并重写 get_offset()。
## 轨迹是"飞了多久 → 相对出生点的偏移"的纯函数，不保存状态，
## 所以同一个轨迹资源可以给很多架敌机共用。
## 基类本身 = 原地悬停。


func get_offset(_t: float) -> Vector3:
	return Vector3.ZERO
