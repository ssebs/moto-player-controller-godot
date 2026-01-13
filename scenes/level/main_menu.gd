class_name MainMenu extends Control

@export var levels: Array[PackedScene] = [
	preload("res://scenes/level/main_level.tscn"),
	preload("res://scenes/level/track_level.tscn"),
]

@onready var city_level_btn: Button = %CityLevelBtn
@onready var race_track_level_btn: Button = %RaceTrackLevelBtn


func _ready() -> void:
	city_level_btn.pressed.connect(_on_city_level_pressed)
	race_track_level_btn.pressed.connect(_on_race_track_level_pressed)

func _input(event):
	if event.is_action_pressed("brake_rear"):
		_on_city_level_pressed()
	if event.is_action_pressed("gear_up"):
		_on_race_track_level_pressed()
	

func _on_city_level_pressed() -> void:
	get_tree().change_scene_to_packed(levels[0])


func _on_race_track_level_pressed() -> void:
	get_tree().change_scene_to_packed(levels[1])
