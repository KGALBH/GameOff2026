extends Node
@warning_ignore_start("unused_signal")
## 全局信号总线（Autoload 名：SignalBus）。
## 所有跨物体的游戏事件都在这里定义和发出，任何脚本都能直接监听：
##   SignalBus.player_hit.connect(_on_player_hit)
## 发出：SignalBus.player_hit.emit(source)

# —— 玩家 ——
## 玩家受到伤害（被敌机撞到等）。source = 造成伤害的物体。血量系统接这个。
signal player_hit(source: Node)

# —— 敌机 ——
## 敌机撞到了玩家。
signal enemy_hit_player(enemy: Node3D, player: Node3D)
## 敌机被打爆。
signal enemy_died(enemy: Node3D)
## 一个编队的敌机全部消失。killed = 被打爆的架数，total = 总架数（killed == total 即全歼）。
signal formation_finished(formation: Node3D, killed: int, total: int)

# —— 关卡 ——
## 关卡开始。
signal level_started(level: Resource)
## 某一波开始出发。index = 在 LevelData.waves 里的序号。
signal wave_started(level: Resource, index: int)
## 关卡所有波次都结束。
signal level_finished(level: Resource)
