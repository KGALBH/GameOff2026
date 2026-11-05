@tool
class_name EnemyPath
extends RefCounted
## 敌机轨迹的纯数学部分（无状态、静态函数）。
## 运行时的 Enemy 和编辑器里的轨迹预览共用这一份公式，保证"预览看到的 = 游戏里飞的"。

enum Pattern {
	STRAIGHT,  ## 直线
	SINE,      ## 正弦波（左右蛇形）
	ZIGZAG,    ## 折线（之字形）
	CIRCLE,    ## 绕前进方向画圈（螺旋前进）
}


## 规范化前进方向（零向量时默认从深处朝屏幕外）。
static func forward(direction: Vector3) -> Vector3:
	return direction.normalized() if direction.length() > 0.001 else Vector3.BACK


## 摆动用的横向轴：从深处飞的左右摆，从侧面飞的在画面平面(XY)里摆。
static func side_axis(fwd: Vector3) -> Vector3:
	var side: Vector3 = fwd.cross(Vector3.BACK)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	return side.normalized()


## 与前进方向、横向轴都垂直的第三根轴。
static func up_axis(fwd: Vector3, side: Vector3) -> Vector3:
	return side.cross(fwd).normalized()


## t 秒时相对出发点的总位移 = 沿前进方向直走 + 横向摆动。
static func displacement(direction: Vector3, speed: float, pattern: int, amplitude: float,
		frequency: float, phase: float, t: float) -> Vector3:
	var fwd: Vector3 = forward(direction)
	var side: Vector3 = side_axis(fwd)
	var up: Vector3 = up_axis(fwd, side)
	return fwd * speed * t + wobble(pattern, amplitude, frequency, phase, t, side, up)


## 横向摆动部分。
static func wobble(pattern: int, amplitude: float, frequency: float, phase: float, t: float,
		side: Vector3, up: Vector3) -> Vector3:
	var a: float = TAU * (frequency * t + phase)
	match pattern:
		Pattern.SINE:
			return side * amplitude * sin(a)
		Pattern.ZIGZAG:
			# 三角波：-1 ~ 1 来回
			var tri: float = 2.0 * absf(2.0 * fposmod(a / TAU, 1.0) - 1.0) - 1.0
			return side * amplitude * tri
		Pattern.CIRCLE:
			return (side * cos(a) + up * sin(a)) * amplitude
	return Vector3.ZERO
