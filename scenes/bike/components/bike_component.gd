class_name BikeComponent extends Node

# Shared state
var state: BikeState

func bike_setup(bike_state: BikeState, _bike_input: BikeInput):
    state = bike_state

func bike_update(_delta):
    pass

func bike_reset():
    pass
