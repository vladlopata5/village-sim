extends RefCounted
## Development commands only. All entities enter the normal world lifecycle.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Resources = preload("res://scripts/resource_type.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Building = preload("res://scripts/building_instance.gd")
const Generator = preload("res://scripts/resident_generator.gd")
var world: Node
var generator := Generator.new(937,"debug")
var _building_sequence := 1
func available() -> bool: return OS.is_debug_build() and is_instance_valid(world) and world.ready_for_play
func rejected(reason: String) -> Dictionary: return {"ok":false,"created":0,"objects":[],"reason":reason}
func building_catalog() -> Array:
	var result: Array = []
	for category in preload("res://scripts/building_type.gd").Type.values():
		var definition = Definition.for_type(category)
		if definition.player_buildable and ResourceLoader.exists("res://scenes/building_layouts/%s.tscn" % definition.id): result.append(definition)
	return result
func _positions(point: Vector3, count: int, spacing: float, residents: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not point.is_finite(): return result
	# Deterministic bounded square rings. No A* queries or navigation edits per item.
	for ring in range(12):
		for z in range(-ring,ring+1):
			for x in range(-ring,ring+1):
				if maxi(absi(x),absi(z))!=ring: continue
				var candidate := Coordinates.from_plane(Coordinates.world_plane(point)+Vector2(x,z)*spacing)
				if not world.navigation.is_world_walkable(candidate): continue
				var radius: float = Geometry.RESIDENT_RADIUS if residents else 0.05
				var box := Rect2(Coordinates.world_plane(candidate)-Vector2.ONE*radius,Vector2.ONE*radius*2)
				if not world.runtime_placement_blockers.first_overlap(box).is_empty(): continue
				result.append(candidate)
				if result.size()==count: return result
	return result
func spawn_residents(point: Vector3, count: int, profession: int) -> Dictionary:
	if not available(): return rejected("Debug команды доступны только в development build")
	if count<1 or count>50 or profession not in Profession.Type.values(): return rejected("Некорректное количество или профессия")
	var positions := _positions(point,count,1.0,true)
	var objects: Array = []
	var unassigned := 0
	for position in positions:
		var data = generator.generate()
		while world.find_resident(data.id)!=null: data=generator.generate()
		data.profession=profession # Legitimate unassigned data if normal assignment fails.
		world.register_spawned_resident(data,position)
		world.player_control.assign_profession(data.id,profession)
		if profession!=Profession.Type.NONE and data.work_location_id.is_empty(): unassigned+=1
		objects.append(data)
	return {"ok":not objects.is_empty(),"created":objects.size(),"objects":objects,"reason":"Создано жителей: %d / %d. Без места работы: %d" % [objects.size(),count,unassigned]}
func spawn_resources(point: Vector3, count: int, resource: int) -> Dictionary:
	if not available(): return rejected("Debug команды недоступны")
	if count<1 or count>100 or resource not in Resources.Type.values() or not point.is_finite(): return rejected("Некорректное количество, ресурс или позиция")
	var placed: Dictionary=world.place_ground_resources(resource,count,Coordinates.to_sim(point))
	var objects: Array=[]
	for id in placed.stack_ids:
		var stack=world.ground_resources.get_by_id(id)
		if stack!=null and stack not in objects: objects.append(stack)
	return {"ok":placed.placed>0,"created":placed.placed,"objects":objects,"discarded":placed.discarded,"reason":"Создано ресурсов: %d / %d" % [placed.placed,count]}
func spawn_building(point: Vector3, definition: Definition) -> Dictionary:
	if not available(): return rejected("Debug команды недоступны")
	if definition==null or not definition.player_buildable or not point.is_finite(): return rejected("Недопустимый тип или координаты")
	var layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
	if not ResourceLoader.exists("res://scenes/building_layouts/%s.tscn" % definition.id): return rejected("Нет authored layout")
	var layout: Node = layouts.create(definition)
	var valid: bool = layouts.validate(layout,definition)
	layout.free()
	if not valid: return rejected("Некорректная геометрия layout")
	var validator = preload("res://scripts/world_3d/building_placement_3d.gd").new()
	validator.grid=world.build_grid
	validator.ground_resources=world.ground_resources
	validator.runtime_blockers=world.runtime_placement_blockers
	validator.entrance_zones=world.entrance_zones
	validator.setup(world.buildings)
	validator.select(definition)
	validator.update_world_position(point)
	if not validator.can_place(): return rejected(validator.validation_reason())
	var id := StringName("debug_building_%04d" % _building_sequence)
	while world.player_control.get_building(id)!=null:
		_building_sequence+=1
		id=StringName("debug_building_%04d" % _building_sequence)
	_building_sequence+=1
	var building := Building.new(id,definition,Coordinates.to_sim(validator.world_position),Building.State.BUILT)
	world.buildings.append(building)
	world._show_building(building) # Ordinary view/activation/container/grid/services hooks.
	return {"ok":true,"created":1,"objects":[building],"reason":"Создано готовое здание: %s (%s)" % [building.display_name,id]}
func advance_to_time(hour: int, minute: int) -> Dictionary:
	if not available(): return rejected("Debug команды недоступны")
	if hour<0 or hour>23 or minute<0 or minute>59: return rejected("Некорректное время")
	world.game_time.debug_set_time_of_day(hour,minute)
	return {"ok":true,"reason":"Время: %s (только вперёд)" % world.game_time.get_clock_text()}
func next_day() -> Dictionary:
	if not available(): return rejected("Debug команды недоступны")
	world.game_time.debug_next_day()
	return {"ok":true,"reason":"Следующий день: 00:00"}

func paint_terrain(point: Vector3, kind: int, width: int = 2) -> Dictionary:
	if not available() or not point.is_finite() or width<1 or width>8:return rejected("Некорректная кисть местности")
	var first: Vector2i=world.build_grid.world_to_cell(point)
	var cells: Array=[]
	for y in width:
		for x in width:cells.append(first+Vector2i(x,y))
	if not world.paint_terrain(cells,kind):return rejected("Клетки заняты, используются заданием или недопустимы для изменения")
	return {"ok":true,"created":cells.size(),"objects":[],"reason":"Изменено клеток: %d"%cells.size()}

var _clay_sequence := 1
func spawn_clay_deposit(point: Vector3) -> Dictionary:
	if not available() or not point.is_finite():return rejected("Некорректная позиция залежи")
	var radius: float=preload("res://scripts/balance_config.gd").ROCK_PHYSICAL_RADIUS
	var cells: Array=world.build_grid.footprint_cells(point,Vector2i(4,4))
	var reason: String=world.build_grid.validation_reason(cells)
	if not reason.is_empty():return rejected(reason)
	for cell in cells:
		if world.ground_resources.get_at(cell)!=null or (world.farm_fields.state(cell)!=world.farm_fields.State.BARE or world.farm_fields.claimed(cell)):return rejected("Клетка занята ресурсами или полем")
	var box:=Rect2(Coordinates.world_plane(point)-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
	if not world.runtime_placement_blockers.first_overlap(box).is_empty():return rejected("Место занято объектом")
	if not world.entrance_zones.validation_reason(box,box).is_empty():return rejected("Нельзя закрывать вход здания")
	var id:=StringName("clay_%04d"%_clay_sequence)
	while world.rock_views.has(id):
		_clay_sequence+=1;id=StringName("clay_%04d"%_clay_sequence)
	_clay_sequence+=1
	var deposit=preload("res://scripts/clay_deposit_data.gd").new(id,Coordinates.to_sim(point))
	world._register_rock(deposit)
	return {"ok":true,"created":1,"objects":[deposit],"reason":"Создана залежь глины: %d единиц"%deposit.stock}
