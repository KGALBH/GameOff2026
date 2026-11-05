@tool
class_name LevelData
extends Resource
## 一个关卡 = 一张出怪时间表。新建 .tres → 在 waves 里一行行添加 WaveEntry。

## 关卡名。
@export var level_name: String = "新关卡"
## 波次列表（按顺序；AFTER_PREVIOUS 指的是列表里的上一行）。
@export var waves: Array[WaveEntry] = []
## 最后一波结束后，再等几秒算通关。
@export var end_delay: float = 2.0
