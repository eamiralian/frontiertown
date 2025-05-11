# WorldGenerator.gd
extends Node

# Signal emitted when world generation is complete.
signal world_generated(map_data, families)

# Map configuration
var map_width: int = 100      # Number of cells horizontally.
var map_height: int = 100     # Number of cells vertically.
var tile_size: int = 32       # (Optional) Visual size for rendering later.

# Tile type constants
const TILE_GRASS = 3
const TILE_WATER = 6
const TILE_HILL  = 11
const TILE_ROCK  = 2

# Each tile represents 2 meters of terrain.
var tile_m: float = 2.0

# Noise generators:
# "terrain_noise" for determining base terrain (water, grass, hills, rocks).
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
	# Initialize the terrain noise.
	# Using world coordinates where each tile is 2m, a 50m period means frequency = 1/50 = 0.02.
	terrain_noise.seed = randi()
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX  # Corrected constant.
	terrain_noise.domain_warp_fractal_octaves = 3
	terrain_noise.domain_warp_frequency = 1.0 / 50.0  # Roughly a 50-meter period.
	terrain_noise.domain_warp_fractal_gain = 0.5

	# Initialize the grass noise.
	# A finer frequency provides variation over roughly 20m.
	grass_noise.seed = randi() + 1000  # Ensure a different seed.
	grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX  # Corrected constant.
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
	emit_signal("world_generated", map_data, families)
	print("World generated. Map dimensions: ", map_width, "x", map_height)
	#print("Number of family groups: ", families.size())


func generate_map() -> void:
	map_data.clear()
	for x in range(map_width):
		map_data.append([])
		for y in range(map_height):
			# Convert grid coordinates (x,y) into world coordinates in meters.
			var world_x = x * tile_m
			var world_y = y * tile_m
			# Use terrain noise to get a value for the tile, normalized to 0..1.
			var raw_val = terrain_noise.get_noise_2d(world_x, world_y)
			var norm_val = (raw_val + 1.0) / 2.0

			var tile_dict = {}  # Dictionary containing tile properties.

			# Determine tile type:
			if norm_val < 0.2:
				tile_dict["type"] = TILE_WATER
			elif norm_val < 0.85:
				tile_dict["type"] = TILE_GRASS
				# For grass tiles, add a smooth height variation.
				var grass_raw = grass_noise.get_noise_2d(world_x, world_y)
				var grass_norm = (grass_raw + 1.0) / 2.0
				# Map noise value to a realistic grass height, in meters.
				tile_dict["grass_height"] = lerp(0.2, 1.0, grass_norm)
			else:
				# For high noise values, choose between hill and rock.
				tile_dict["type"] = TILE_HILL if randf() < 0.5 else TILE_ROCK

			map_data[x].append(tile_dict)

func get_tile_at(x: int, y: int) -> Dictionary:
	if x < 0 or x >= map_width or y < 0 or y >= map_height:
		return {}
	return map_data[x][y]


# Preload our ECS classes.
var EntityClass = preload("res://Entity.gd")
var CreatureClass = preload("res://Creature.gd")

# Helper function to generate a single family member entity.
func generate_family_member(member_id: int, potential_names: Array) -> RefCounted:
	# Create a new entity (our base container).
	var entity = EntityClass.new()
	entity.id = member_id
	# Create the creature component that holds family member data.
	var creature = CreatureClass.new()
	creature.creature_id = member_id
	creature.display_name = potential_names[randi() % potential_names.size()]
	creature.age = max(6 + randi() % 18, 6 + randi() % 18)   # Age range, weighted
	creature.relationships = []	   # Relationships will be filled later.
	# Attach the creature component to our entity.
	entity.add_component("creature", creature)
	return entity


func generate_families(family_count: int) -> void:
	families.clear()
	var attempts = 0
	var max_attempts = family_count * 10   # Prevent potential infinite loops.
	
	# Dummy data for generating names
	var potential_names = ["John", "Mary", "Alex", "Emma", "Robert", "Olivia", "James", "Sophia", "William", "Ava"]
	
	# Place families only on grass tiles.
	while families.size() < family_count and attempts < max_attempts:
		attempts += 1
		var x = randi() % map_width
		var y = randi() % map_height
		if map_data[x][y]["type"] == TILE_GRASS:
			# Decide on a random number of family members (e.g., between 2 and 6).
			var num_members = 2 + randi() % 5
			var members = []
			
			# Generate each family member as an entity with a creature component.
			for i in range(num_members):
				var member = generate_family_member(i, potential_names)
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
				"status": "traveling"
			}
			families.append(family)
