# WorldGenerator.gd
extends Node

# Signal emitted when world generation is complete.
signal world_generated(map_data, families)

# Map configuration
var map_width: int = 100 # Number of cells horizontally.
var map_height: int = 100 # Number of cells vertically.
var tile_size: int = 32 # (Optional) Visual size for rendering later.
var EROSION_SIM_ENABLED: bool = true # Flag to enable/disable erosion simulation

# Tile type constants
const TILE_GRASS = 3
const TILE_WATER = 6
const TILE_DIRT = 11
const TILE_ROCK = 2

# Elevation thresholds
const WATER_LEVEL = 0.30 # Below this is water
const DIRT_LEVEL = 0.45 # Below this (and above water) is dirt
const GRASS_LEVEL = 0.75 # Below this (and above dirt) is grass
						  # Above this is rock

# Each tile represents 2 meters of terrain.
var tile_m: float = 2.0

# Noise generators:
# "heightmap_noise" for generating the primary elevation map.
var heightmap_noise = FastNoiseLite.new()
# "terrain_noise" for determining base terrain (water, grass, ddirt, rocks).
# var terrain_noise = FastNoiseLite.new() # No longer used for primary terrain type
# "grass_noise" for generating smooth variation in grass height.
# var grass_noise = FastNoiseLite.new() # No longer used for primary terrain type

@export_group("Visualization")
# @export var progress_label: Label  # Label for showing erosion progress - commented out editor assignment
var progress_label: Label # Label for showing erosion progress - will be found at runtime
@export var update_interval: int = 10 # Update visual every X iterations

# Hydraulic Erosion Parameters
@export_group("Hydraulic Erosion")
@export var erosion_iterations: int = 25000 # Total number of droplets to simulate
@export var max_droplet_lifetime: int = 100 # Max steps a droplet can take
@export var inertia: float = 0.1 # How much momentum is preserved (0-1)
@export var sediment_capacity_factor: float = 4.0 # Multiplier for how much sediment water can carry
@export var min_sediment_capacity: float = 0.01 # Minimum sediment capacity
@export var erosion_speed: float = 0.3 # How quickly terrain is eroded
@export var deposition_speed: float = 0.3 # How quickly sediment is deposited
@export var evaporate_speed: float = 0.01 # How quickly water evaporates from a droplet
@export var gravity: float = 4.0 # Affects droplet acceleration
@export var initial_water_volume: float = 2.0 # Starting water in a droplet
@export var initial_speed: float = 2.0 # Starting speed of a droplet


# Data storage for the generated world.
# Each cell will be a dictionary with terrain details.
var map_data = [] # 2D array containing dictionaries for each tile.
var families = [] # List of family dictionaries.

var sim_manager_is_ready: bool = false
var renderer_is_ready: bool = false
var world_renderer_node: Node = null # Add reference for WorldRenderer
var camera_node: Camera2D = null # Add reference for Camera to scale label

func _ready() -> void:
	print("WorldGenerator: Initialized. Waiting for SimulationManager and WorldRenderer to be ready.")
	randomize()

	# Find and set the progress label at runtime
	var label_path = "/root/SimulationManager/UIManager/Label"
	progress_label = get_node_or_null(label_path)
	if progress_label:
		print("WorldGenerator: Found progress label at ", label_path)
	else:
		print("WorldGenerator: Progress label not found at ", label_path, " - will attempt to find it after SimulationManager is initialized.")
		
		# Try alternative path based on user request
		var alt_label_path = "/root/simmanager/uimanager/label"
		progress_label = get_node_or_null(alt_label_path)
		if progress_label:
			print("WorldGenerator: Found progress label at alternate path: ", alt_label_path)
		else:
			print("WorldGenerator: Progress label not found at alternate path either")

	# Initialize the heightmap noise for overall elevation.
	heightmap_noise.seed = randi()
	heightmap_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	heightmap_noise.frequency = 0.005 # Lower frequency for larger features (e.g., 200m period if tile_m=2)
	heightmap_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	heightmap_noise.fractal_octaves = 4
	heightmap_noise.fractal_lacunarity = 2.0
	heightmap_noise.fractal_gain = 0.5

	# Enable and configure domain warp for heightmap_noise to create more river-like features
	heightmap_noise.domain_warp_enabled = true
	heightmap_noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX # Reverted to DOMAIN_WARP_SIMPLEX
	heightmap_noise.domain_warp_amplitude = 100.0 # Increased from 50.0, controls the intensity of the warp.
	heightmap_noise.domain_warp_frequency = 0.005 # Decreased from 0.01, frequency of the warp noise for larger features.
	heightmap_noise.domain_warp_fractal_type = FastNoiseLite.FRACTAL_FBM
	heightmap_noise.domain_warp_fractal_octaves = 3 # Increased from 2 for more detail in warp.
	heightmap_noise.domain_warp_fractal_lacunarity = 2.0
	heightmap_noise.domain_warp_fractal_gain = 0.5


	# Initialize the terrain noise (currently used for domain warping, might be repurposed or removed later).
	# Using world coordinates where each tile is 2m, a 50m period means frequency = 1/50 = 0.02.
	# terrain_noise.seed = randi() + 500 # Different seed
	# terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX  # Corrected constant.
	# terrain_noise.domain_warp_fractal_octaves = 3
	# terrain_noise.domain_warp_frequency = 1.0 / 50.0  # Roughly a 50-meter period.
	# terrain_noise.domain_warp_fractal_gain = 0.5

	# Initialize the grass noise.
	# A finer frequency provides variation over roughly 20m.
	# grass_noise.seed = randi() + 1000  # Ensure a different seed.
	# grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX  # Corrected constant.
	# grass_noise.frequency = 0.02 # Example: A bit finer than main terrain features.
	# For domain warp, frequency is interpreted differently.
	# Let's keep domain warp settings for grass_noise if it's to be used for variation on grass tiles later.
	# grass_noise.domain_warp_fractal_octaves = 2
	# grass_noise.domain_warp_frequency = 1.0 / 20.0   # Roughly a 20-meter period.
	# grass_noise.domain_warp_fractal_gain = 0.7

	# Connect to SimulationManager's initialized signal (assuming it's the parent)
	var sim_manager = get_parent()
	if sim_manager and sim_manager.has_signal("initialized"):
		var error_sim = sim_manager.connect("initialized", _on_simulation_manager_initialized)
		if error_sim == OK:
			print("WorldGenerator: Connected to SimulationManager's initialized signal.")
		else:
			printerr("WorldGenerator: Failed to connect to SimulationManager's initialized signal. Error: ", error_sim)
	else:
		printerr("WorldGenerator: Could not find SimulationManager as parent or it lacks 'initialized' signal.")

	var world_renderer_path = "/root/SimulationManager/WorldRenderer"
	var world_renderer = get_node_or_null(world_renderer_path)
	if world_renderer:
		if world_renderer.has_signal("initialized"):
			var error_renderer = world_renderer.connect("initialized", _on_renderer_initialized)
			if error_renderer == OK:
				print("WorldGenerator: Connected to WorldRenderer's initialized signal.")
			else:
				printerr("WorldGenerator: Failed to connect to WorldRenderer's initialized signal. Error: ", error_renderer)
		else:
			printerr("WorldGenerator: WorldRenderer at '", world_renderer_path, "' lacks 'initialized' signal.")
	else:
		printerr("WorldGenerator: Could not find WorldRenderer at '", world_renderer_path, "'.")

	if world_renderer: # Check if world_renderer was found before assigning
		self.world_renderer_node = world_renderer # Store the reference
	else:
		printerr("WorldGenerator: world_renderer_node is null, droplet visualization will be disabled.")
		
	# Find the camera node
	var camera_path = "/root/SimulationManager/Camera2D"
	camera_node = get_node_or_null(camera_path)
	if camera_node:
		print("WorldGenerator: Found camera at ", camera_path)
	else:
		printerr("WorldGenerator: Could not find camera at ", camera_path)

func _on_simulation_manager_initialized() -> void:
	print("WorldGenerator: Received initialized signal from SimulationManager.")
	sim_manager_is_ready = true
	
	# If progress label wasn't found during _ready, try again now
	if not progress_label:
		var label_path = "/root/SimulationManager/UIManager/Label"
		progress_label = get_node_or_null(label_path)
		if progress_label:
			print("WorldGenerator: Found progress label at ", label_path, " after SimulationManager initialization")
		else:
			# Try the user-specified path
			var alt_label_path = "/root/simmanager/uimanager/label"
			progress_label = get_node_or_null(alt_label_path)
			if progress_label:
				print("WorldGenerator: Found progress label at alternate path: ", alt_label_path)
			else:
				print("WorldGenerator: Label not found at specific paths - will try recursive search")
				# Try a recursive search to find the label if the path isn't exactly as expected
				progress_label = _find_label_recursive(get_tree().root)
				if progress_label:
					print("WorldGenerator: Found progress label through recursive search")
				else:
					print("WorldGenerator: Could not find any Label node in the scene tree")
	
	_attempt_world_generation()

func _on_renderer_initialized() -> void:
	print("WorldGenerator: Received initialized signal from WorldRenderer.")
	renderer_is_ready = true
	_attempt_world_generation()

func _attempt_world_generation() -> void:
	if sim_manager_is_ready and renderer_is_ready:
		print("WorldGenerator: Both SimulationManager and WorldRenderer are ready. Starting world generation.")
		generate_world()
	elif not get_parent() or not get_parent().has_signal("initialized"):
		print("WorldGenerator: Still waiting for SimulationManager.")
	elif not get_tree().root.has_node("WorldRenderer") or not get_node("/root/WorldRenderer").has_signal("initialized"):
		print("WorldGenerator: Still waiting for WorldRenderer.")


func generate_world() -> void:
	generate_map()
	generate_families(5) # Create a starting group of 5 families.
	print("World generated. Map dimensions: ", map_width, "x", map_height)
	emit_signal("world_generated", map_data, families)
	#print("Number of family groups: ", families.size())


func generate_map() -> void:
	map_data.clear()
	map_data.resize(map_width) # Initialize outer array

	# Phase 1: Generate initial heightmap using noise
	print("WorldGenerator: Generating initial heightmap...")
	for x in range(map_width):
		map_data[x] = []
		map_data[x].resize(map_height) # Initialize inner array
		for y in range(map_height):
			var world_x = x * tile_m
			var world_y = y * tile_m
			
			var raw_height_val = heightmap_noise.get_noise_2d(world_x, world_y)
			var norm_height_val = (raw_height_val + 1.0) / 2.0 # Normalize to 0-1
			map_data[x][y] = {"height": norm_height_val}

	# Phase 2: Start hydraulic erosion simulation incrementally
	if (EROSION_SIM_ENABLED) {
		print("WorldGenerator: Starting hydraulic erosion simulation...")
		_simulate_hydraulic_erosion() # This will start the incremental simulation
	}
	
	# The simulation will be processed frame-by-frame using the _process method
	# Tile types will be determined after erosion completes in _finish_erosion()
	
	# Phase 3: Determine initial tile types while erosion runs
	print("WorldGenerator: Assigning initial tile types...")
	
	for x in range(map_width):
		for y in range(map_height):
			var final_height_val = map_data[x][y]["height"]
			var tile_dict = map_data[x][y] # Get existing dict, or ensure it's a dict

			if not typeof(tile_dict) == TYPE_DICTIONARY: # Should always be a dict now
				tile_dict = {"height": final_height_val}
				map_data[x][y] = tile_dict

			# Determine tile type based on final_height_val using helper function
			tile_dict["type"] = _get_tile_type_for_height(final_height_val)
			
			# map_data[x][y] is already updated as tile_dict is a reference (if it was a dict)
			# If it wasn't, we re-assigned it.

func get_tile_at(x: int, y: int) -> Dictionary:
	if x < 0 or x >= map_width or y < 0 or y >= map_height:
		return {}
	return map_data[x][y]


# Preload our ECS classes.
var EntityClass = preload("res://Entity.gd")
var CreatureClass = preload("res://Creature.gd")

# Helper function to generate a single family member entity.
func generate_family_member(member_id: int, potential_names: Array, family_anchor_x: int, family_anchor_y: int) -> RefCounted:
	# Create a new entity (our base container).
	var entity = EntityClass.new()
	entity.id = member_id
	# Create the creature component that holds family member data.
	var creature = CreatureClass.new()
	creature.creature_id = member_id
	creature.display_name = potential_names[randi() % potential_names.size()]
	creature.age = max(6 + randi() % 18, 6 + randi() % 18) # Age range, weighted
	creature.relationships = [] # Relationships will be filled later.

	# Assign individual position near family anchor
	var creature_x: int
	var creature_y: int
	var placement_attempts: int = 0
	var max_placement_attempts: int = 10 # Try a few times to find a spot
	var found_spot: bool = false
	var individual_cluster_radius: float = 3.0 # How far individuals can be from family anchor (in tiles)

	while not found_spot and placement_attempts < max_placement_attempts:
		placement_attempts += 1
		var angle = randf_range(0, 2 * PI)
		var radius = randf_range(0, individual_cluster_radius)
		creature_x = int(round(family_anchor_x + cos(angle) * radius))
		creature_y = int(round(family_anchor_y + sin(angle) * radius))

		# Check bounds and tile type (prefer grass)
		if creature_x >= 0 and creature_x < map_width and \
		   creature_y >= 0 and creature_y < map_height and \
		   map_data[creature_x][creature_y]["type"] == TILE_GRASS:
			found_spot = true
	
	if not found_spot: # Fallback: place at family anchor if no suitable spot found nearby
		creature_x = family_anchor_x
		creature_y = family_anchor_y
		# Ensure anchor itself is valid (should be, as family is placed on grass)
		if not (creature_x >= 0 and creature_x < map_width and \
				creature_y >= 0 and creature_y < map_height and \
				map_data[creature_x][creature_y]["type"] == TILE_GRASS):
			# This case should be rare if family placement is correct.
			# If even the anchor is bad, something is wrong upstream or map is too small/constrained.
			# For now, we'll still assign it, but it might cause issues.
			printerr("WorldGenerator: Could not place creature ", member_id, " on grass, even at family anchor ", family_anchor_x, ",", family_anchor_y)


	creature.map_pos_x = creature_x
	creature.map_pos_y = creature_y

	# Attach the creature component to our entity.
	entity.add_component("creature", creature)
	return entity


func generate_families(family_count: int) -> void:
	families.clear()
	var attempts = 0
	var max_attempts = family_count * 20 # Increased max_attempts slightly

	# Dummy data for generating names
	var potential_names = ["John", "Mary", "Alex", "Emma", "Robert", "Olivia", "James", "Sophia", "William", "Ava"]

	var first_family_pos: Vector2 = Vector2.ZERO
	var cluster_radius: float = 25.0 # Max distance from the first family for other families (in tiles)
	var placement_attempts_within_radius: int = 15 # How many times to try placing near the first family

	# Place families only on grass tiles.
	while families.size() < family_count and attempts < max_attempts:
		attempts += 1
		var x: int
		var y: int
		var found_spot_for_family: bool = false

		if families.size() == 0:
			# Place the first family randomly to establish a cluster center
			var first_family_placement_attempts = 0
			while not found_spot_for_family and first_family_placement_attempts < 100:
				first_family_placement_attempts += 1
				x = randi() % map_width
				y = randi() % map_height
				if map_data[x][y]["type"] == TILE_GRASS:
					first_family_pos = Vector2(x, y)
					found_spot_for_family = true
			if not found_spot_for_family:
				printerr("WorldGenerator: Could not place the first family on a grass tile after many attempts.")
				# Optionally, could try to place it anywhere if strict clustering start fails
				# For now, we'll let the main loop attempt counter handle further retries if needed.
				continue # Skip to next attempt in the main while loop
		else:
			# Place subsequent families near the first family
			for _i in range(placement_attempts_within_radius):
				var angle = randf_range(0, 2 * PI)
				var radius = randf_range(0, cluster_radius)
				x = int(round(first_family_pos.x + cos(angle) * radius))
				y = int(round(first_family_pos.y + sin(angle) * radius))

				# Clamp to map bounds
				x = clamp(x, 0, map_width - 1)
				y = clamp(y, 0, map_height - 1)

				if map_data[x][y]["type"] == TILE_GRASS:
					found_spot_for_family = true
					break
			
			if not found_spot_for_family:
				# Fallback: if couldn't find a spot in the cluster, try a completely random spot for this attempt
				var fallback_attempts = 0
				while not found_spot_for_family and fallback_attempts < 5: # Try a few random spots
					fallback_attempts += 1
					x = randi() % map_width
					y = randi() % map_height
					if map_data[x][y]["type"] == TILE_GRASS:
						found_spot_for_family = true
				if not found_spot_for_family:
					continue # Skip to next attempt in the main while loop if fallback also fails

		if found_spot_for_family:
			# Decide on a random number of family members (e.g., between 2 and 6).
			var num_members = 2 + randi() % 5
			var members = []
			
			# Generate each family member as an entity with a creature component.
			for i in range(num_members):
				var member = generate_family_member(i, potential_names, x, y)
				members.append(member)
			
			# Populate relationships for each family member.
			# In this simple example, every creature stores the IDs (indexes) of all its siblings.
			for i in range(num_members):
				var creature_comp = members[i].get_component("creature")
				var rels = []
				for j in range(num_members):
					if i != j:
						rels.append(j)
				creature_comp.relationships = rels
			
			# Create the family dictionary with the generated members.
			var family = {
				"id": families.size(),
				"position": Vector2(x, y),
				"members": members,
				"status": "traveling",
				"anchor_x": x,
				"anchor_y": y,
			}
			families.append(family)

	if families.size() < family_count:
		print("WorldGenerator: Warning - Could not place all requested families. Placed: ", families.size(), " of ", family_count)

# --- Hydraulic Erosion Implementation ---

func _get_height_at(px: float, py: float, current_map_data: Array) -> float:
	var x: int = floori(px)
	var y: int = floori(py)
	if x < 0 or x >= map_width or y < 0 or y >= map_height:
		return 1.0 # Treat out-of-bounds as high to prevent flowing off easily, or use actual edge height
	if x + 1 >= map_width or y + 1 >= map_height: # Near edge, no interpolation
		return current_map_data[x][y]["height"]

	# Bilinear interpolation for smoother height reading
	var h00 = current_map_data[x][y]["height"]
	var h10 = current_map_data[x + 1][y]["height"]
	var h01 = current_map_data[x][y + 1]["height"]
	var h11 = current_map_data[x + 1][y + 1]["height"]

	var tx = px - x
	var ty = py - y

	var h_interp_top = lerp(h00, h10, tx)
	var h_interp_bottom = lerp(h01, h11, tx)
	return lerp(h_interp_top, h_interp_bottom, ty)


func _calculate_gradient(px: float, py: float, current_map_data: Array) -> Vector2:
	var x: int = floori(px)
	var y: int = floori(py)

	# Ensure we are within bounds for gradient calculation (needs 1 cell margin)
	if x <= 0 or x >= map_width - 1 or y <= 0 or y >= map_height - 1:
		# Simplified: return zero gradient at edges or use a fixed outward flow if preferred
		return Vector2.ZERO

	var hx1 = _get_height_at(px + 1.0, py, current_map_data)
	var hx_1 = _get_height_at(px - 1.0, py, current_map_data)
	var hy1 = _get_height_at(px, py + 1.0, current_map_data)
	var hy_1 = _get_height_at(px, py - 1.0, current_map_data)

	return Vector2(hx1 - hx_1, hy1 - hy_1) # Gradient points uphill, negate for downhill


# Variables for tracking erosion simulation state
var _erosion_in_progress: bool = false
var _erosion_current_iteration: int = 0
var _erosion_start_time: int = 0
var _erosion_last_update_time: int = 0
var _erosion_prng: RandomNumberGenerator = null

# Process a batch of erosion iterations each frame
func _process(_delta: float) -> void:
	if _erosion_in_progress:
		_process_erosion_batch()
	
	# Update label size with camera zoom changes even outside of erosion updates
	if progress_label and progress_label.visible:
		_configure_label_style(progress_label)

# Begin the erosion simulation - now just sets up and schedules work
func _simulate_hydraulic_erosion() -> void:
	if _erosion_in_progress:
		print("Hydraulic erosion simulation already in progress!")
		return
		
	_erosion_prng = RandomNumberGenerator.new()
	_erosion_prng.randomize()
	_erosion_current_iteration = 0
	_erosion_in_progress = true
	
	# Initial rendering of terrain before erosion
	if world_renderer_node:
		if world_renderer_node.has_method("clear_entire_droplet_layer"):
			world_renderer_node.clear_entire_droplet_layer() # Clear droplet layer immediately
		
		# Optional: Pre-render the whole terrain before erosion
		for x in range(map_width):
			for y in range(map_height):
				var height_val = map_data[x][y]["height"]
				var tile_type = _get_tile_type_for_height(height_val)
				if world_renderer_node.has_method("update_terrain_tile_visual"):
					world_renderer_node.update_terrain_tile_visual(x, y, tile_type)

	# Set up progress reporting
	_erosion_start_time = Time.get_ticks_msec()
	_erosion_last_update_time = _erosion_start_time
	
	print("Hydraulic erosion simulation started - will process incrementally")
	if progress_label:
		progress_label.text = "Erosion: 0% - Starting simulation..."
		_configure_label_style(progress_label)

# Process a batch of erosion iterations each frame to avoid freezing
func _process_erosion_batch() -> void:
	var batch_size = 50 # Process this many droplets per frame - adjust for performance
	var update_freq_ms = 1000 # Update progress more frequently with this approach
	
	# Process a batch of iterations
	for batch_i in range(batch_size):
		if _erosion_current_iteration >= erosion_iterations:
			_finish_erosion()
			return
		
		# Update progress periodically
		if _erosion_current_iteration % update_interval == 0:
			var current_time = Time.get_ticks_msec()
			if current_time - _erosion_last_update_time > update_freq_ms:
				_erosion_last_update_time = current_time
				var elapsed_time = float(current_time - _erosion_start_time) / 1000.0 # in seconds
				var progress_ratio = float(_erosion_current_iteration) / float(erosion_iterations)
				var estimated_total = elapsed_time / max(0.001, progress_ratio) # Avoid division by zero
				var remaining_time = estimated_total - elapsed_time
				var percent = progress_ratio * 100.0
				
				# Update progress display
				_update_progress_display(_erosion_current_iteration, erosion_iterations, elapsed_time, remaining_time)
				
				# Print to console periodically
				if _erosion_current_iteration % 10000 == 0: # Reduce console spam
					print("Erosion: %d/%d (%.1f%%) | Time: %.1fs | Est. Remaining: %.1fs" %
						[_erosion_current_iteration, erosion_iterations, percent, elapsed_time, remaining_time])
		
		# More frequent progress log for debugging
		if _erosion_current_iteration % 1000 == 0:
			print("Erosion iteration: ", _erosion_current_iteration, "/", erosion_iterations)

		# Increment the iteration counter
		_erosion_current_iteration += 1
		
		# Simulate one droplet
		_simulate_single_droplet()

# Simulate a single erosion droplet
func _simulate_single_droplet() -> void:
	# Spawn droplet at a random position
	var pos_x: float = _erosion_prng.randf_range(0, map_width - 1)
	var pos_y: float = _erosion_prng.randf_range(0, map_height - 1)
	var dir_x: float = 0.0
	var dir_y: float = 0.0
	var speed: float = initial_speed
	var water: float = initial_water_volume
	var sediment: float = 0.0

	for _lifetime in range(max_droplet_lifetime):
		var int_px: int = floori(pos_x)
		var int_py: int = floori(pos_y)

		# Check bounds for the droplet's current cell
		if int_px <= 0 or int_px >= map_width - 1 or int_py <= 0 or int_py >= map_height - 1:
			break # Droplet flowed off edge or got stuck at border

		var gradient: Vector2 = _calculate_gradient(pos_x, pos_y, map_data)

		# Update direction with gradient and inertia
		dir_x = dir_x * inertia - gradient.x * (1.0 - inertia)
		dir_y = dir_y * inertia - gradient.y * (1.0 - inertia)

		# Normalize direction vector
		var dir_len = sqrt(dir_x * dir_x + dir_y * dir_y)
		if dir_len < 0.0001: # Avoid division by zero if gradient is flat
			# Pick a random direction if flat, or break
			dir_x = _erosion_prng.randf_range(-1.0, 1.0)
			dir_y = _erosion_prng.randf_range(-1.0, 1.0)
			dir_len = sqrt(dir_x * dir_x + dir_y * dir_y)
			if dir_len < 0.0001: break # Still flat, stop droplet
		
		dir_x /= dir_len
		dir_y /= dir_len

		# New position based on direction
		var new_pos_x = pos_x + dir_x
		var new_pos_y = pos_y + dir_y

		# Check bounds for new position
		if new_pos_x <= 0 or new_pos_x >= map_width - 1 or new_pos_y <= 0 or new_pos_y >= map_height - 1:
			break # Droplet is about to flow off edge

		var current_height = _get_height_at(pos_x, pos_y, map_data)
		var new_height = _get_height_at(new_pos_x, new_pos_y, map_data)
		var delta_height = new_height - current_height # Negative if moving downhill

		var sediment_capacity = max(min_sediment_capacity, water * speed * sediment_capacity_factor) # Capacity increases with water and speed

		if delta_height < 0: # Moving downhill (new_height is lower)
			# Erode or deposit based on capacity
			var amount_to_erode = - delta_height # Positive value for how much lower the new point is
			
			if sediment + amount_to_erode < sediment_capacity:
				# Can pick up more sediment
				var erode_actual = min(amount_to_erode, (sediment_capacity - sediment)) * erosion_speed
				# Apply erosion to the *current* cell (int_px, int_py)
				var old_height = map_data[int_px][int_py]["height"]
				map_data[int_px][int_py]["height"] = max(0.0, map_data[int_px][int_py]["height"] - erode_actual)
				sediment += erode_actual
				
				# Update terrain visual if height change leads to type change
				if world_renderer_node and world_renderer_node.has_method("update_terrain_tile_visual") and _erosion_current_iteration % update_interval == 0:
					var new_type = _get_tile_type_for_height(map_data[int_px][int_py]["height"])
					var old_type = _get_tile_type_for_height(old_height)
					if new_type != old_type:
						world_renderer_node.update_terrain_tile_visual(int_px, int_py, new_type)
			else:
				# At capacity, or will exceed capacity; deposit some sediment instead
				var deposit_actual = min(sediment, (sediment + amount_to_erode - sediment_capacity)) * deposition_speed
				var old_height = map_data[int_px][int_py]["height"]
				map_data[int_px][int_py]["height"] = min(1.0, map_data[int_px][int_py]["height"] + deposit_actual)
				sediment -= deposit_actual
				
				# Update terrain visual if height change leads to type change
				if world_renderer_node and world_renderer_node.has_method("update_terrain_tile_visual") and _erosion_current_iteration % update_interval == 0:
					var new_type = _get_tile_type_for_height(map_data[int_px][int_py]["height"])
					var old_type = _get_tile_type_for_height(old_height)
					if new_type != old_type:
						world_renderer_node.update_terrain_tile_visual(int_px, int_py, new_type)
		else: # Moving uphill or flat - deposit sediment
			var deposit_actual = min(sediment, delta_height + (sediment * deposition_speed * 0.1)) # Deposit more if going uphill, less if flat
			deposit_actual = max(0, deposit_actual) # Ensure not negative
			var old_height = map_data[int_px][int_py]["height"]
			map_data[int_px][int_py]["height"] = min(1.0, map_data[int_px][int_py]["height"] + deposit_actual)
			sediment -= deposit_actual
			sediment = max(0, sediment)
			
			# Update terrain visual if height change leads to type change
			if world_renderer_node and world_renderer_node.has_method("update_terrain_tile_visual") and _erosion_current_iteration % update_interval == 0:
				var new_type = _get_tile_type_for_height(map_data[int_px][int_py]["height"])
				var old_type = _get_tile_type_for_height(old_height)
				if new_type != old_type:
					world_renderer_node.update_terrain_tile_visual(int_px, int_py, new_type)

		# Update speed and water
		speed = sqrt(max(0.01, speed * speed + delta_height * gravity)) # Keep a minimum speed
		water *= (1.0 - evaporate_speed)

		if water <= 0.001:
			break # Droplet evaporated

		pos_x = new_pos_x
		pos_y = new_pos_y
		
		# Visualize droplet path
		if world_renderer_node and _erosion_current_iteration % update_interval == 0:
			# Direct call since we're in the main thread
			if world_renderer_node.has_method("set_droplet_tile"):
				world_renderer_node.set_droplet_tile(floori(pos_x), floori(pos_y))

# Called when erosion simulation is complete
func _finish_erosion() -> void:
	_erosion_in_progress = false
	var total_time = str((Time.get_ticks_msec() - _erosion_start_time) / 1000.0)
	print("Hydraulic erosion simulation complete. Total time:", total_time)
	if progress_label:
		progress_label.text = "Erosion: 100% - Complete " + total_time
		
		# Apply consistent styling and zoom scaling
		_configure_label_style(progress_label)

	# Clear the droplet layer to remove all droplet visualizations
	if world_renderer_node and world_renderer_node.has_method("clear_entire_droplet_layer"):
		print("Clearing droplet visualization layer")
		world_renderer_node.clear_entire_droplet_layer()

	# Ensure all tile types are updated based on final heights
	for x in range(map_width):
		for y in range(map_height):
			var height_val = map_data[x][y]["height"]
			var tile_type = _get_tile_type_for_height(height_val)
			map_data[x][y]["type"] = tile_type
			
			# Update visuals for any changes
			if world_renderer_node and world_renderer_node.has_method("update_terrain_tile_visual"):
				world_renderer_node.update_terrain_tile_visual(x, y, tile_type)
	
	print("WorldGenerator: Hydraulic erosion simulation complete, terrain fully updated.")

# Update progress display with detailed information
func _update_progress_display(iteration: int, total: int, elapsed_time: float, remaining_time: float) -> void:
	if progress_label:
		var percent = (float(iteration) / float(total)) * 100.0
		progress_label.text = "Erosion: %d/%d (%.1f%%) | Time: %.1fs | Est. Remaining: %.1fs" % [
			iteration, total, percent, elapsed_time, remaining_time
		]
		
		# Apply consistent styling and zoom scaling
		_configure_label_style(progress_label)
		
		# Ensure label stays in the viewport
		var parent_node = progress_label.get_parent()
		if not (parent_node is CanvasLayer):
			# If not already in a CanvasLayer, just ensure it's visible in global space
			progress_label.position = progress_label.global_position

# Helper function to determine tile type based on height value
func _get_tile_type_for_height(height_val: float) -> int:
	if height_val < WATER_LEVEL:
		return TILE_WATER
	elif height_val < DIRT_LEVEL:
		return TILE_DIRT
	elif height_val < GRASS_LEVEL:
		return TILE_GRASS
	else:
		return TILE_ROCK

# Helper function to recursively search for a Label node in the scene tree
func _find_label_recursive(node: Node) -> Label:
	# Check if this node is a Label
	if node is Label:
		return node
	
	# Recursively search through all children
	for child in node.get_children():
		var found_label = _find_label_recursive(child)
		if found_label:
			return found_label
	
	# No Label found in this branch
	return null

# Helper function to configure label styling with consistent look and scaling
func _configure_label_style(label: Label) -> void:
	if not label:
		return
		
	# Set font size and scale with camera zoom
	if not label.has_theme_font_size_override("font_size"):
		label.add_theme_font_size_override("font_size", 24) # Larger base font size
	
	# Add background for better visibility if not already set
	if not label.has_theme_stylebox_override("normal"):
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color(0, 0, 0, 0.5) # Semi-transparent black background
		style_box.corner_radius_top_left = 5
		style_box.corner_radius_top_right = 5
		style_box.corner_radius_bottom_left = 5
		style_box.corner_radius_bottom_right = 5
		style_box.set_content_margin_all(8) # Padding
		label.add_theme_stylebox_override("normal", style_box)
	
	# Add a white text color for better readability
	if not label.has_theme_color_override("font_color"):
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1)) # White text
	
	# Add shadow for better contrast against any background
	if not label.has_theme_constant_override("shadow_offset_x"):
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7)) # Dark shadow
		label.add_theme_constant_override("shadow_outline_size", 1)
		
	# Ensure label is visible
	label.visible = true
	
	# Scale label size inversely with camera zoom
	if camera_node:
		var zoom_factor = camera_node.zoom.x # Assume uniform zoom
		var font_size = 24 # Base font size
		var scaled_size = int(font_size / zoom_factor)
		# Clamp to ensure it doesn't get too large or too small
		scaled_size = clamp(scaled_size, 12, 48)
		label.add_theme_font_size_override("font_size", scaled_size)
		
		# Position the label properly
		var viewport_size = get_viewport().get_visible_rect().size
		label.global_position = Vector2(10, 10) # Padding from top-left corner
		label.size = Vector2(viewport_size.x * 0.8, 40) # Width is 80% of viewport
