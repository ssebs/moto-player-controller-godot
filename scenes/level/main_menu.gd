class_name MainMenu extends Control

signal do_close()

func _input(_event):
    if Input.is_anything_pressed():
        do_close.emit()
        on_close_menu()

func on_close_menu():
    self.hide()
    self.set_process_input(false)
