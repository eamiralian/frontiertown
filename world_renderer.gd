extends Node

signal initialized # Add this new signal

# A reference to the TileMap node in our scene (assumed to be set up in the editor)
var tile_map: TileMap

const TERRAIN_ATLAS_SOURCE_ID = 0
const CREATURE_ATLAS_SOURCE_ID = 1 # Assuming creature atlas is source_id 1
const TERRAIN_LAYER = 0 # Terrain on the bottom layer
const CREATURE_LAYER = 1 # Creatures on a layer above terrain

func _ready() -> void:
	# Get our TileMap child. In the scene, name it "TileMap".
	tile_map = $TileMap
	
	var sim_manager = get_parent()
	#print("WorldRenderer: Parent node is ", sim_manager)
	if sim_manager:
		var error_connect = sim_manager.connect("simulation_world_ready", _on_simulation_world_ready)
		if error_connect != OK:
			printerr("WorldRenderer: Failed to connect to SimulationManager's simulation_world_ready signal. Error: ", error_connect)
	else:
		printerr("WorldRenderer: Could not find SimulationManager node at /root/SimulationManager.")
	
	print("WorldRenderer initialized, waiting on generated world...")
	call_deferred("emit_signal", "initialized")

# Callback when the Simulation Manager signals that the world is ready.
func _on_simulation_world_ready(world_data, generated_families) -> void:
	render_world(world_data, generated_families)

func render_world(world_data: Array, generated_families: Array) -> void:
	print("Rendering world and creatures...")
	# Clear any existing tiles.
	if tile_map: # Good practice to check if tile_map is valid
		tile_map.clear_layer(TERRAIN_LAYER) 
		tile_map.clear_layer(CREATURE_LAYER)
	else:
		printerr("WorldRenderer: tile_map is null!")
		return

	# --- Assuming Godot 4.x ---
	# You need to know the source_id from your TileSet for the tiles you\'re using.
	# If you have one atlas, its source_id is often 0.
	# var source_id_to_use = 0 # Replaced by TERRAIN_ATLAS_SOURCE_ID

	for x in range(world_data.size()):
		for y in range(world_data[x].size()):
			var tile_info: Dictionary = world_data[x][y]
			var tile_type: int = tile_info.get("type", -1) # This is your integer tile ID

			if tile_type != -1:
				# In Godot 4, you need to convert your integer \'tile_type\' 
				# into \'atlas_coords\' (a Vector2i) for the given \'source_id\'.
				# How you do this depends on how your TileSet is structured 
				# and what \'tile_type\' represents.

				# Example: If \'tile_type\' directly corresponds to the x-coordinate 
				# in your atlas, and all tiles are on the y-coordinate 0:
				# var atlas_coords = Vector2i(tile_type, 0) 
				
				# Example: If \'tile_type\' is a flat index in an atlas of a known width:
				var atlas_width = 4 # Replace with your atlas\'s width in tiles
				var atlas_coords = Vector2i(tile_type % atlas_width, tile_type / atlas_width)

				if tile_map:
					tile_map.set_cell(TERRAIN_LAYER, Vector2i(x, y), TERRAIN_ATLAS_SOURCE_ID, atlas_coords)
	
	# Render families (creatures)
	var creature_atlas_width = 4 # As specified, 4 tiles wide
	for family in generated_families:
		for member_entity in family.members:
			var creature_component = member_entity.get_component("creature")
			if creature_component:
				var creature_x = creature_component.map_pos_x
				var creature_y = creature_component.map_pos_y
				
				# Ensure positions are valid before trying to render
				if creature_x != -1 and creature_y != -1:
					# Pick a random tile from the creature atlas (0 to 3 for x-coordinate)
					var creature_atlas_coord_x = randi() % creature_atlas_width
					var creature_atlas_coords = Vector2i(creature_atlas_coord_x, 0) # Assuming all 4 tiles are in the first row
					
					if tile_map:
						#print("WorldRenderer: Rendering creature ", creature_component.creature_id, " at (", creature_x, ",", creature_y, ") with atlas coords ", creature_atlas_coords)
						tile_map.set_cell(CREATURE_LAYER, Vector2i(creature_x, creature_y), CREATURE_ATLAS_SOURCE_ID, creature_atlas_coords)
				else:
					printerr("WorldRenderer: Creature ", creature_component.creature_id, " has invalid map position (", creature_x, ",", creature_y, ")")
			else:
				printerr("WorldRenderer: Found a family member entity without a creature component.")

	print("Rendering complete.")
