class_name EnemyAttack
extends Resource
## 敌机攻击方式基类。新攻击方式：继承它并重写 fire()。
## 不保存状态（冷却计时放在 EnemyPlane 里），所以同一个攻击资源可以给很多架敌机共用。
## 基类本身 = 不攻击。

## 两次攻击的间隔（秒）。
@export var cooldown: float = 1.5
## 出生后多久第一次攻击（秒）。
@export var first_delay: float = 1.0


func fire(_enemy: EnemyPlane) -> void:
	pass
