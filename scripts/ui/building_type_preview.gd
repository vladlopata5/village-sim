extends VBoxContainer
## Read-only BuildingDefinition presentation; never creates a building instance.
const Resources = preload("res://scripts/resource_type.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Grid = preload("res://scripts/build_grid.gd")
func show_definition(definition: RefCounted) -> void:
	$Name.text = definition.display_name
	var lines := PackedStringArray()
	for resource in definition.construction_requirements:
		lines.append("%s: %d" % [Resources.display_name(resource),definition.construction_requirements[resource]])
	$Materials.text = "Необходимые ресурсы:\n" + ("\n".join(lines) if not lines.is_empty() else "Не требуются")
	var cells: Vector2i = definition.footprint_cells
	$Footprint.text = "Footprint: %d × %d build cells\n%.1f × %.1f world units" % [cells.x,cells.y,cells.x*Grid.CELL_SIZE,cells.y*Grid.CELL_SIZE]
	var roles := PackedStringArray()
	if definition.worker_profession != Profession.Type.NONE:
		roles.append("%s: %s" % [Profession.display_name(definition.worker_profession),str(definition.worker_capacity) if definition.worker_capacity > 0 else "без лимита"])
	if definition.porter_capacity > 0: roles.append("Носильщики: %d" % definition.porter_capacity)
	if definition.housing_capacity > 0: roles.append("Жильцы: %d" % definition.housing_capacity)
	$Roles.text = "\n".join(roles)
	$Roles.visible = not roles.is_empty()
