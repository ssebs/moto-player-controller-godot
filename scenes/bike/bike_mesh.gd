@tool
class_name BikeMesh extends Node3D

@export var bike_config: BikeConfig:
	set(value):
		bike_config = value
		if bike_config:
			_apply_mesh()

@export_tool_button("Load from Config") var load_btn = _load_from_config
@export_tool_button("Save to Config") var save_btn = _save_to_config

# Node references
var mesh_container: Node3D
var front_wheel_marker: Marker3D
var rear_wheel_marker: Marker3D

var _mesh_instance: Node3D = null


func _ready():
	_cache_node_refs()


func _cache_node_refs():
	if not is_inside_tree():
		return
	mesh_container = get_node_or_null("MeshContainer")
	front_wheel_marker = get_node_or_null("WheelMarkers/FrontWheelMarker")
	rear_wheel_marker = get_node_or_null("WheelMarkers/RearWheelMarker")


func _apply_mesh():
	_cache_node_refs()

	# Clear existing mesh
	if _mesh_instance:
		_mesh_instance.queue_free()
		_mesh_instance = null

	if not bike_config or not bike_config.mesh_scene:
		return

	if not mesh_container:
		return

	# Instance new mesh
	_mesh_instance = bike_config.mesh_scene.instantiate()
	_mesh_instance.scale = bike_config.mesh_scale
	mesh_container.rotation_degrees = bike_config.mesh_rotation
	mesh_container.add_child(_mesh_instance)


func _load_from_config():
	if not bike_config:
		push_error("No BikeConfig assigned")
		return

	_cache_node_refs()
	_apply_mesh()

	# Apply wheel marker positions from config
	front_wheel_marker.position = bike_config.front_wheel_position
	rear_wheel_marker.position = bike_config.rear_wheel_position


func _save_to_config():
	if not bike_config:
		push_error("No BikeConfig assigned")
		return

	_cache_node_refs()

	# Read wheel marker positions into config
	bike_config.front_wheel_position = front_wheel_marker.position
	bike_config.rear_wheel_position = rear_wheel_marker.position

	# Save resource to disk
	var err = ResourceSaver.save(bike_config, bike_config.resource_path)
	if err != OK:
		push_error("Failed to save BikeConfig: %s" % err)
	else:
		print("Saved BikeConfig to: %s" % bike_config.resource_path)
