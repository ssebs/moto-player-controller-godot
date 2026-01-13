class_name TailLightMod extends BikeComponent

@onready var mesh: MeshInstance3D = %Mesh

var surface_mat: StandardMaterial3D

func _ready():
    add_to_group("Mods", true)


func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    surface_mat = mesh.get_active_material(0)
    

func turn_on_light():
    surface_mat.emission_enabled = true

func turn_off_light():
    surface_mat.emission_enabled = false


# hack - gets called in _apply_bike_config
func _bike_reset():
    if not player_controller:
        return
    transform = player_controller.bike_resource.taillight_transform
