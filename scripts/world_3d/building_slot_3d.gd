@tool
extends Marker3D
## Editor-authored physical place. No profession/job/home ownership.
const BuildingPurpose = preload("res://scripts/building_slot_purpose.gd")
const Purpose = BuildingPurpose.Type
@export var local_id: StringName
@export var purpose: BuildingPurpose.Type = Purpose.WORKER
@export var minimum_level := 1
var occupant: String = ""
