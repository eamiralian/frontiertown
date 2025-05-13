# WorldGenerator.gd
extends Node

# Signal emitted when world generation is complete.
signal world_generated(map_data, families)

# Map configuration
var map_width: int = 1000      # Number of cells horizontally.
var map_height: int = 1000     # Number of cells vertically.
var tile_size: int = 32       # (Optional) Visual size for rendering later.

# Tile type constants
const TILE_GRASS = 3
const TILE_WATER = 6
const TILE_DIRT  = 11
const TILE_ROCK  = 2

# Each tile represents 2 meters of terrain.
var tile_m: float = 2.0

# Noise generators:
# "heightmap_noise" for generating the primary elevation map.
var heightmap_noise = FastNoiseLite.new()
# "terrain_noise" for determining base terrain (water, grass, ddirt, rocks).
var terrain_noise = FastNoiseLite.new()
# "grass_noise" for generating smooth variation in grass height.
var grass_noise = FastNoiseLite.new()

# Data storage for the generated world.
# Each cell will be a dictionary with terrain details.
var map_data = []      # 2D array containing dictionaries for each tile.
var families = []      # List of family dictionaries.

var sim_manager_is_ready: bool = false
var renderer_is_ready: bool = false

func _ready() -> void:
	print("WorldGenerator: Initialized. Waiting for SimulationManager and WorldRenderer to be ready.")
	randomize()

	# Initialize the heightmap noise for overall elevation.
	heightmap_noise.seed = randi()
	heightmap_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	heightmap_noise.frequency = 0.005  # Lower frequency for larger features (e.g., 200m period if tile_m=2)
	heightmap_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	heightmap_noise.fractal_octaves = 4
	heightmap_noise.fractal_lacunarity = 2.0
	heightmap_noise.fractal_gain = 0.5

	# Initialize the terrain noise (currently used for domain warping, might be repurposed or removed later).
	# Using world coordinates where each tile is 2m, a 50m period means frequency = 1/50 = 0.02.
	terrain_noise.seed = randi() + 500 # Different seed
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX  # Corrected constant.
	terrain_noise.domain_warp_fractal_octaves = 3
	terrain_noise.domain_warp_frequency = 1.0 / 50.0  # Roughly a 50-meter period.
	terrain_noise.domain_warp_fractal_gain = 0.5

	# Initialize the grass noise.
	# A finer frequency provides variation over roughly 20m.
	grass_noise.seed = randi() + 1000  # Ensure a different seed.
	grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX  # Corrected constant.
	# grass_noise.frequency = 0.02 # Example: A bit finer than main terrain features.
	# For domain warp, frequency is interpreted differently.
	# Let's keep domain warp settings for grass_noise if it's to be used for variation on grass tiles later.
	grass_noise.domain_warp_fractal_octaves = 2
	grass_noise.domain_warp_frequency = 1.0 / 20.0   # Roughly a 20-meter period.
	grass_noise.domain_warp_fractal_gain = 0.7

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


	# generate_world() # Moved to _attempt_world_generation()

func _on_simulation_manager_initialized() -> void:
	print("WorldGenerator: Received initialized signal from SimulationManager.")
	sim_manager_is_ready = true
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
	generate_families(5)     # Create a starting group of 5 families.
	print("World generated. Map dimensions: ", map_width, "x", map_height)
	emit_signal("world_generated", map_data, families)
	#print("Number of family groups: ", families.size())


func generate_map() -> void:
	map_data.clear()

	# Define elevation thresholds for tile types (normalized 0.0 to 1.0)
	const WATER_LEVEL = 0.30  # Below this is water
	const DIRT_LEVEL  = 0.45  # Below this (and above water) is dirt
	const GRASS_LEVEL = 0.75  # Below this (and above dirt) is grass
							  # Above this is rock

	for x in range(map_width):
		map_data.append([])
		for y in range(map_height):
			var world_x = x * tile_m
			var world_y = y * tile_m
			
			# Use heightmap_noise for primary elevation.
			var raw_height_val = heightmap_noise.get_noise_2d(world_x, world_y)
			var norm_height_val = (raw_height_val + 1.0) / 2.0

			var tile_dict = {}

			# Determine tile type based on elevation from heightmap_noise:
			if norm_height_val < WATER_LEVEL:
				tile_dict["type"] = TILE_WATER
			elif norm_height_val < DIRT_LEVEL:
				tile_dict["type"] = TILE_DIRT
			elif norm_height_val < GRASS_LEVEL:
				tile_dict["type"] = TILE_GRASS
				# Optional: If grass height variation is still desired on grass tiles,
				# it could be added here using grass_noise, but independent of the main elevation.
				# For now, let's keep it simple.
				# var grass_raw = grass_noise.get_noise_2d(world_x, world_y)
				# var grass_norm = (grass_raw + 1.0) / 2.0
				# tile_dict["grass_height"] = lerp(0.1, 0.5, grass_norm) # Smaller variation
			else:
				tile_dict["type"] = TILE_ROCK
			
			# --- Old logic using terrain_noise and randf() - now replaced ---
			# # Use terrain noise to get a value for the tile, normalized to 0..1.
			# var raw_val = terrain_noise.get_noise_2d(world_x, world_y)
			# var norm_val = (raw_val + 1.0) / 2.0
			#
			# # Determine tile type:
			# if norm_val < 0.25:
			#	 tile_dict["type"] = TILE_WATER
			# elif norm_val < 0.65:
			#	 tile_dict["type"] = TILE_GRASS
			#	 # For grass tiles, add a smooth height variation.
			#	 #var grass_raw = grass_noise.get_noise_2d(world_x, world_y)
			#	 #var grass_norm = (grass_raw + 1.0) / 2.0
			#	 ## Map noise value to a realistic grass height, in meters.
			#	 #tile_dict["grass_height"] = lerp(0.2, 1.0, grass_norm)
			# else:
			#	 # For high noise values, choose between dirt and rock.
			#	 tile_dict["type"] = TILE_DIRT if randf() < 0.5 else TILE_ROCK
			# --- End of old logic ---

			map_data[x].append(tile_dict)

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
	creature.age = max(6 + randi() % 18, 6 + randi() % 18)   # Age range, weighted
	creature.relationships = []	   # Relationships will be filled later.

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
	var max_attempts = family_count * 20   # Increased max_attempts slightly

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
