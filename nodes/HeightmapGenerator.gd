tool
extends ColorRect

class Island:
	var bezier := PoolVector2Array()
	var seed_offset := 0.0
	var cell_size_min := 0.0
	var cell_size_max := 0.0
	var origin := Vector2(0, 0)

var seedV = 0.0
var islands = []

func _ready():
	material = material.duplicate()
	randomize()
	new_seed()
	random_islands(4, Vector2(500.0, 500.0), Vector2(250.0, 250.0))
	update_islands()
	_process(0.0)

func _process(_delta):
	material.set_shader_param("_world_transform", get_global_transform())

func point_on_circle(f, r):
	return Vector2(sin(f*6.28), cos(f*6.28)) * r

func generate_cubic_bezier(center:Vector2, size:Vector2):
	var bezier = PoolVector2Array()
	bezier.resize(4)
	bezier[0] = -size
	bezier[1] = Vector2(randf()*2.0-1.0, randf()*2.0-1.0) * size * 4.0
	bezier[2] = Vector2(randf()*2.0-1.0, randf()*2.0-1.0) * size * 4.0
	bezier[3] = size.rotated(randf()*PI)
	var rotation = randf()*PI*2.0
	for i in 4:
		bezier[i] = bezier[i].rotated(rotation)
		bezier[i] += center
	return bezier

func random_islands(num_islands, radius:Vector2, island_size:Vector2):
	islands = []
	islands.resize(num_islands)
	for i in num_islands:
		var f = (i+0.5) / num_islands
		var island = Island.new()
		island.origin = point_on_circle(f, radius) + radius * 2.0
		island.bezier = generate_cubic_bezier(island.origin, island_size)
		island.seed_offset = randf()*100.0
		island.cell_size_min = 250.0
		island.cell_size_max = 400.0
		islands[i] = island

func update_islands():
	var img = Image.new()
	img.create(islands.size()*3, 1, false, Image.FORMAT_RGBAF)
	img.lock()
	for i in islands.size():
		var island = islands[i]
		img.set_pixel(i*3+0, 0, Color(island.bezier[0].x, island.bezier[0].y, island.bezier[1].x, island.bezier[1].y))
		img.set_pixel(i*3+1, 0, Color(island.bezier[2].x, island.bezier[2].y, island.bezier[3].x, island.bezier[3].y))
		img.set_pixel(i*3+2, 0, Color(island.seed_offset, island.cell_size_min,  island.cell_size_max, 1.0))
	img.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	material.set_shader_param("_islands", tex)
	material.set_shader_param("_num_islands", islands.size())
	print("New islands set")


func new_seed():
	seedV = randi()+randf()
	material.set_shader_param("_world_seed", seedV/1000)