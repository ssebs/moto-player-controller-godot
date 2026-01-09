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
var head_target: Marker3D
var left_arm_target: Marker3D
var right_arm_target: Marker3D
var butt_target: Marker3D
var left_leg_target: Marker3D
var right_leg_target: Marker3D
var front_wheel_marker: Marker3D
var rear_wheel_marker: Marker3D

var _mesh_instance: Node3D = null


func _ready():
	_cache_node_refs()


func _cache_node_refs():
	if not is_inside_tree():
		return
	mesh_container = get_node_or_null("MeshContainer")
	head_target = get_node_or_null("Targets/HeadTarget")
	left_arm_target = get_node_or_null("Targets/LeftArmTarget")
	right_arm_target = get_node_or_null("Targets/RightArmTarget")
	butt_target = get_node_or_null("Targets/ButtTarget")
	left_leg_target = get_node_or_null("Targets/LeftLegTarget")
	right_leg_target = get_node_or_null("Targets/RightLegTarget")
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
	# _mesh_instance.rotation_degrees = bike_config.mesh_rotation
	mesh_container.add_child(_mesh_instance)


func _load_from_config():
	if not bike_config:
		push_error("No BikeConfig assigned")
		return

	_cache_node_refs()
	_apply_mesh()

	# Apply marker positions from config
	head_target.position = bike_config.head_target_position
	head_target.rotation = bike_config.head_target_rotation
	left_arm_target.position = bike_config.left_arm_target_position
	left_arm_target.rotation = bike_config.left_arm_target_rotation
	right_arm_target.position = bike_config.right_arm_target_position
	right_arm_target.rotation = bike_config.right_arm_target_rotation
	butt_target.position = bike_config.butt_target_position
	butt_target.rotation = bike_config.butt_target_rotation
	left_leg_target.position = bike_config.left_leg_target_position
	left_leg_target.rotation = bike_config.left_leg_target_rotation
	right_leg_target.position = bike_config.right_leg_target_position
	right_leg_target.rotation = bike_config.right_leg_target_rotation
	front_wheel_marker.position = bike_config.front_wheel_position
	rear_wheel_marker.position = bike_config.rear_wheel_position

	# _mesh_instance.scale = bike_config.mesh_scale
	mesh_container.rotation_degrees = bike_config.mesh_rotation # TODO: fixme


func _save_to_config():
	if not bike_config:
		push_error("No BikeConfig assigned")
		return

	_cache_node_refs()

	# Read marker positions into config
	bike_config.head_target_position = head_target.position
	bike_config.head_target_rotation = head_target.rotation
	bike_config.left_arm_target_position = left_arm_target.position
	bike_config.left_arm_target_rotation = left_arm_target.rotation
	bike_config.right_arm_target_position = right_arm_target.position
	bike_config.right_arm_target_rotation = right_arm_target.rotation
	bike_config.butt_target_position = butt_target.position
	bike_config.butt_target_rotation = butt_target.rotation
	bike_config.left_leg_target_position = left_leg_target.position
	bike_config.left_leg_target_rotation = left_leg_target.rotation
	bike_config.right_leg_target_position = right_leg_target.position
	bike_config.right_leg_target_rotation = right_leg_target.rotation
	bike_config.front_wheel_position = front_wheel_marker.position
	bike_config.rear_wheel_position = rear_wheel_marker.position

	# Save resource to disk
	var err = ResourceSaver.save(bike_config, bike_config.resource_path)
	if err != OK:
		push_error("Failed to save BikeConfig: %s" % err)
	else:
		print("Saved BikeConfig to: %s" % bike_config.resource_path)
