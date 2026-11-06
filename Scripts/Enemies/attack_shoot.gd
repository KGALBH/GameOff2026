class_name AttackShoot
extends EnemyAttack
## 发射子弹：可以瞄准玩家或朝固定方向打，可以一次打出扇形的多发。

## 子弹场景（需要挂 Bullet 脚本）。
@export var bullet_scene: PackedScene
## 子弹速度（米/秒）。
@export var bullet_speed: float = 15.0
## 勾选 = 朝玩家当前位置打；不勾 = 朝 direction 打。
@export var aim_at_player: bool = true
## 不瞄准时的射击方向（世界坐标）。默认 +Z，朝玩家所在的一侧。
@export var direction: Vector3 = Vector3(0, 0, 1)
## 一次打几发。
@export var bullet_count: int = 1
## 多发时扇形的总角度（度），在 XZ 平面（左右）展开。
@export var spread_degrees: float = 30.0


func fire(enemy: EnemyPlane) -> void:
	if bullet_scene == null:
		return
	var dir: Vector3 = direction.normalized()
	if aim_at_player:
		var player: Node3D = enemy.get_player()
		if player:
			dir = (player.global_position - enemy.global_position).normalized()

	for i in bullet_count:
		var angle: float = 0.0
		if bullet_count > 1:
			angle = deg_to_rad(lerpf(-spread_degrees * 0.5, spread_degrees * 0.5, float(i) / (bullet_count - 1)))
		var bullet: Bullet = bullet_scene.instantiate() as Bullet
		bullet.shooter = enemy
		enemy.get_tree().current_scene.add_child(bullet)
		bullet.global_position = enemy.global_position
		bullet.velocity = dir.rotated(Vector3.UP, angle) * bullet_speed
