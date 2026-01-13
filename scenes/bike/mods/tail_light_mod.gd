class_name TailLightMod extends BikeComponent

var emission_something

func _ready():
    add_to_group("Mods", true)


func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    print("bike_setup in taillightmod")

func turn_on_light():
    pass

func turn_off_light():
    pass


# hack - gets called in _apply_bike_config
func _bike_reset():
    if not player_controller:
        return
    transform = player_controller.bike_resource.taillight_transform
