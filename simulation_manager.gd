# SimulationManager.gd
extends Node

signal initialized # Add this new signal

# Signals to communicate simulation events to the UI or other systems.
signal tick_updated(tick)
signal simulation_saved(file_path)
signal simulation_loaded(file_path)
signal simulation_world_ready(world_data, generated_families)
signal initial_camera_focus_ready(focus_position_pixels) # New signal for camera

# --- Simulation Tick Variables ---
var tick_interval: float = 0.0166666666666667 # Seconds per simulation tick.
var time_accumulator: float = 0.0            # Accumulates delta time.
var tick_count: int = 0                      # Global tick counter.

# --- Data-driven Entity Storage ---
# Entities are stored in a dictionary.
# They can be simple data dictionaries or instances of custom classes.
var entities := {}
var world_data = []
var world_generator_node # To store reference to world_generator

# --- Stubbed Heavy Simulation Data ---
var wind_simulation_data := {}
var sound_simulation_data := {}
var water_simulation_data := {}

# --- Multithreading Variables ---
var heavy_simulation_thread: Thread
var thread_running: bool = true       # Control flag to stop the heavy simulation thread.

func _ready() -> void:
	# Instance the WorldGenerator.
	var WorldGeneratorScene = preload("res://world_generator.gd")
	world_generator_node = WorldGeneratorScene.new() # Assign to member variable
	
	# Connect to the world_generated signal.
	world_generator_node.connect("world_generated", _on_world_generated)
	
	# Add it as a child so it gets its own _ready() call too.
	add_child(world_generator_node)
	
	# Kick off world generation is now handled by WorldGenerator waiting for signals
	# world_generator.generate_world() # This line should remain commented or removed
	
	# Continue initializing the simulation as needed.
	print("Simulation Manager initialized, waiting on world generation...")
	# Start the heavy simulation thread.
	#heavy_simulation_thread = Thread.new()
	#heavy_simulation_thread.start("_run_heavy_simulation")

	call_deferred("emit_signal", "initialized")
	
func _on_world_generated(generated_map_data, generated_families) -> void:
	world_data = generated_map_data
	
	for family_idx in range(generated_families.size()):
		var family = generated_families[family_idx]

		# Check if family is a Dictionary before trying to access its methods/keys
		if typeof(family) != TYPE_DICTIONARY:
			printerr("SimulationManager: Expected family to be a Dictionary, but got type ", typeof(family), " for family at index ", family_idx, ". Value: ", family)
			continue # Skip this iteration

		# Ensure family structure is as expected, especially after previous edits
		if not family.has("members") or not family.has("anchor_x") or not family.has("anchor_y"):
			printerr("SimulationManager: Family data structure is unexpected for family index ", family_idx, ". Family data: ", family)
			continue

		for human_entity in family["members"]: # human_entity is an EntityClass instance
			# EntityClass instances always have an 'id' property.
			# We check if this ID is valid for use (e.g., not the default -1 if -1 is considered uninitialized).
			# Assuming IDs assigned by world_generator are always >= 0.
			if typeof(human_entity) == TYPE_OBJECT and "id" in human_entity: # Robust check
				if human_entity.id != -1: 
					entities[human_entity.id] = human_entity
				else:
					printerr("SimulationManager: Human entity in family %d has an invalid/uninitialized ID (-1). Entity: %s" % [family_idx, human_entity])
			else:
				printerr("SimulationManager: Item in family[%d].members is not a valid entity object or lacks an ID. Type: %s, Value: %s" % [family_idx, typeof(human_entity), human_entity])

	print("World loaded into Simulation Manager:")
	#print("Map size: ", world_data.size(), " x ", world_data[0].size())
	#print("Number of families: ", generated_families.size())

	# Set initial camera focus on the first family
	if generated_families.size() > 0:
		var first_family = generated_families[0]
		if first_family.has("anchor_x") and first_family.has("anchor_y") and world_generator_node:
			var tile_s = world_generator_node.tile_size
			var focus_x = first_family.anchor_x * tile_s + tile_s / 2.0
			var focus_y = first_family.anchor_y * tile_s + tile_s / 2.0
			#emit_signal("initial_camera_focus_ready", Vector2(focus_x, focus_y))
			#print("SimulationManager: Emitted initial_camera_focus_ready for position: ", Vector2(focus_x, focus_y))
		else:
			printerr("SimulationManager: Could not set initial camera focus. First family data missing or world_generator_node not set.")
	
	# Emit a signal to notify the rest of the system.
	emit_signal("simulation_world_ready", world_data, generated_families)
	
func _exit_tree():
	# Signal the heavy simulation thread to exit and wait for it to finish.
	thread_running = false
	if heavy_simulation_thread and heavy_simulation_thread.is_active():
		heavy_simulation_thread.wait_to_finish()

func _process(delta: float) -> void:
	# Accumulate delta time and handle ticks.
	time_accumulator += delta
	while time_accumulator >= tick_interval:
		time_accumulator -= tick_interval
		_simulation_tick()

func _simulation_tick() -> void:
	tick_count += 1

	# Process data-driven entity updates.
	# Each entity can define its own 'update' method.
	for key in entities.keys():
		var entity = entities[key]
		entity.update(tick_count)
	
	# Update our stubbed heavy simulations (to recently update UI or data pointers).
	_update_heavy_simulation_stub(tick_count)
	
	# Emit a signal to let other systems know a new tick occurred.
	emit_signal("tick_updated", tick_count)

func _update_heavy_simulation_stub(tick: int) -> void:
	# These stubs generate random simulation data.
	# In the future they may be replaced or supplemented with multithreaded computations.
	wind_simulation_data = {"tick": tick, "wind_speed": randf_range(0, 10)}
	sound_simulation_data = {"tick": tick, "ambient_noise": randf_range(0, 5)}
	water_simulation_data = {"tick": tick, "current_flow": randf_range(0, 3)}

func _run_heavy_simulation(user_data) -> void:
	# This function runs in a separate thread to preemptively handle performance-heavy tasks.
	# It runs a simple loop that can later be expanded to include full wind, sound, and water simulation.
	while thread_running:
		# Simulate computation: in a real implementation, you might perform heavy physics or audio processing here.
		OS.delay_msec(10)
		# Note: If you later write shared data from this thread, consider using Mutex objects for thread safety.

# --- Save / Load Functionality ---
func save_simulation_state(file_path: String) -> void:
	var state = {
		"tick_count": tick_count,
		"entities": entities,   # Ensure your entity data is JSON serializable.
		"wind_simulation_data": wind_simulation_data,
		"sound_simulation_data": sound_simulation_data,
		"water_simulation_data": water_simulation_data
	}
	var json_string = JSON.stringify(state)
	var save_file = FileAccess.open("user://savegame.save", FileAccess.WRITE)
	save_file.store_line(json_string)
	emit_signal("simulation_saved", file_path)

func load_simulation_state(file_path: String) -> void:
	if not FileAccess.file_exists("user://savegame.save"):
		return # Error! We don't have a save to load.
	var save_file = FileAccess.open("user://savegame.save", FileAccess.READ)
	while save_file.get_position() < save_file.get_length():
		var json_string = save_file.get_line()

		# Creates the helper class to interact with JSON.
		var json = JSON.new()

		# Check if there is any error while parsing the JSON string, skip in case of failure.
		var parse_result = json.parse(json_string)
		if not parse_result == OK:
			print("JSON Parse Error: ", json.get_error_message(), " in ", json_string, " at line ", json.get_error_line())
			continue

		# Get the data from the JSON object.
		var state = json.data
	
		if typeof(state) == TYPE_DICTIONARY:
			tick_count = state.get("tick_count", 0)
			entities = state.get("entities", {})
			wind_simulation_data = state.get("wind_simulation_data", {})
			sound_simulation_data = state.get("sound_simulation_data", {})
			water_simulation_data = state.get("water_simulation_data", {})
			emit_signal("simulation_loaded", file_path)
		else:
			print("Error: Loaded data is not a dictionary.")
