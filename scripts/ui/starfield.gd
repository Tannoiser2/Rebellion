extends Control
## Sfondo stellato animato (stelle a tre profondità che scorrono piano, qualche nebulosa).

var stars: Array = []
var t := 0.0


func _ready() -> void:
	var g := RandomNumberGenerator.new()
	g.seed = 1138
	for i in 420:
		stars.append({"p": Vector2(g.randf() * 1920, g.randf() * 1080), "z": g.randi_range(1, 3), "b": g.randf_range(0.35, 1.0), "ph": g.randf() * TAU})
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	queue_redraw()


func _draw() -> void:
	var sz := size if size.x > 10 else Vector2(1920, 1080)
	draw_rect(Rect2(Vector2.ZERO, sz), UI.BG)
	# nebulose: dischi sfumati molto tenui
	_glow(Vector2(sz.x * 0.78, sz.y * 0.3), 520, Color(0.35, 0.12, 0.1, 0.06))
	_glow(Vector2(sz.x * 0.2, sz.y * 0.75), 600, Color(0.1, 0.2, 0.42, 0.07))
	for s in stars:
		var z: int = s["z"]
		var p: Vector2 = s["p"]
		var x := fposmod(p.x - t * 4.0 * z, sz.x)
		var y := fposmod(p.y, sz.y)
		var tw := 0.75 + 0.25 * sin(t * 1.7 + s["ph"])
		var c := Color(0.85, 0.92, 1.0, s["b"] * tw * (0.45 + 0.25 * z))
		draw_circle(Vector2(x, y), 0.5 + 0.45 * z, c)


func _glow(c: Vector2, r: float, col: Color) -> void:
	for i in 10:
		var k := 1.0 - i / 10.0
		draw_circle(c, r * k, Color(col.r, col.g, col.b, col.a * 0.35))
