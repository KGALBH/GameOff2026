@tool
class_name WaveEntry
extends Resource
## 关卡时间表里的一行：什么时候、在哪里、出哪个编队。

enum Trigger {
	AT_TIME,          ## 关卡开始后第 time 秒出发
	AFTER_PREVIOUS,   ## 上一波全部消失后再过 time 秒出发
}

## 备注（只给人看，比如"第一波 V 字"）。
@export var note: String = ""
## 要生成的编队。
@export var formation: FormationData
## 编队中心的出发点（世界坐标）。深处一般 z = -160 左右。
@export var position: Vector3 = Vector3(0, 0, -160)
## 触发方式。
@export var trigger: Trigger = Trigger.AT_TIME
## AT_TIME：关卡开始后的秒数；AFTER_PREVIOUS：上一波结束后的等待秒数。
@export var time: float = 0.0
