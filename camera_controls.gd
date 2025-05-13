# RimworldCamera.gd
extends Camera2D

@export_category("Panning")
@export var pan_speed: float = 600.0            # Speed of keyboard/edge panning
@export var screen_edge_margin: int = 35        # Pixel margin for screen edge panning
@export var screen_edge_pan_enabled: bool = false
@export var drag_pan_enabled: bool = true       # Middle mouse button drag

@export_category("Zooming")
@export var zoom_speed_wheel: float = 0.1       # How much each mouse wheel step zooms
@export var zoom_speed_keys: float = 0.15       # How much each key press zooms
@export var min_zoom: float = 0.25              # Smallest zoom value (most zoomed out)
@export var max_zoom: float = 2.5               # Largest zoom value (most zoomed in)

# Internal variables for drag panning
var _is_dragging: bool = false
var _drag_start_mouse_pos: Vector2
var _drag_start_camera_pos: Vector2


func _ready() -> void:
    # This ensures _unhandled_input is called for mouse events, etc.
    set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        # Mouse Wheel Zooming
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
            _apply_zoom(1.0 + zoom_speed_wheel)
            get_viewport().set_input_as_handled() # Consume the event
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
            _apply_zoom(1.0 - zoom_speed_wheel)
            get_viewport().set_input_as_handled()

        # Mouse Drag Panning
        if drag_pan_enabled and event.is_action("camera_drag"): # Checks the input action
            if event.is_pressed():
                _is_dragging = true
                _drag_start_mouse_pos = get_global_mouse_position()
                _drag_start_camera_pos = global_position
                get_viewport().set_input_as_handled()
            else:
                _is_dragging = false
                get_viewport().set_input_as_handled()

    if event is InputEventMouseMotion and _is_dragging:
        var mouse_motion_delta = event.relative # More direct way to get mouse motion
        # Adjust movement by current zoom to make dragging feel consistent
        # When zoomed out (small zoom value), need larger camera movement for same mouse drag
        global_position = _drag_start_camera_pos - mouse_motion_delta * zoom
        get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
    var pan_direction := Vector2.ZERO

    # Keyboard Panning
    if Input.is_action_pressed("camera_pan_left"):
        pan_direction.x -= 1
    if Input.is_action_pressed("camera_pan_right"):
        pan_direction.x += 1
    if Input.is_action_pressed("camera_pan_up"):
        pan_direction.y -= 1
    if Input.is_action_pressed("camera_pan_down"):
        pan_direction.y += 1

    # Screen Edge Panning (only if not currently dragging with mouse)
    if screen_edge_pan_enabled and not _is_dragging:
        var mouse_pos = get_viewport().get_mouse_position()
        var viewport_size = get_viewport().get_visible_rect().size
        
        if mouse_pos.x >= 0 and mouse_pos.x < screen_edge_margin: # Check mouse is within viewport bounds too
            pan_direction.x -= 1
        if mouse_pos.x < viewport_size.x and mouse_pos.x > viewport_size.x - screen_edge_margin:
            pan_direction.x += 1
        if mouse_pos.y >=0 and mouse_pos.y < screen_edge_margin:
            pan_direction.y -= 1
        if mouse_pos.y < viewport_size.y and mouse_pos.y > viewport_size.y - screen_edge_margin:
            pan_direction.y += 1
    
    # Apply Panning
    if pan_direction != Vector2.ZERO:
        # Normalize to prevent faster diagonal movement
        # Panning speed is independent of zoom for keyboard/edge, adjust with 'delta'
        global_position += pan_direction.normalized() * pan_speed * delta

    # Keyboard Zooming
    if Input.is_action_just_pressed("camera_zoom_in_key"):
        _apply_zoom(1.0 - zoom_speed_keys)
    if Input.is_action_just_pressed("camera_zoom_out_key"):
        _apply_zoom(1.0 + zoom_speed_keys)


func _apply_zoom(zoom_factor: float) -> void:
    var new_zoom_value = zoom.x * zoom_factor # Assuming uniform zoom (x and y are the same)
    new_zoom_value = clamp(new_zoom_value, min_zoom, max_zoom)
    zoom = Vector2(new_zoom_value, new_zoom_value)
