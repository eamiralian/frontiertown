extends Node

signal initialized # Add this new signal

# A reference to the TileMap node in our scene (assumed to be set up in the editor)
var tile_map: TileMap

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
	print("Rendering")
	# Clear any existing tiles.
	if tile_map: # Good practice to check if tile_map is valid
		tile_map.clear() # In Godot 4, you might want to clear specific layers: tile_map.clear_layer(0)
	else:
		printerr("WorldRenderer: tile_map is null!")
		return

	# --- Assuming Godot 4.x ---
	var layer_to_use = 0 # Specify which layer you are drawing on (default is 0)
	# You need to know the source_id from your TileSet for the tiles you're using.
	# If you have one atlas, its source_id is often 0.
	var source_id_to_use = 0 

	for x in range(world_data.size()):
		for y in range(world_data[x].size()):
			var tile_info: Dictionary = world_data[x][y]
			var tile_type: int = tile_info.get("type", -1) # This is your integer tile ID

			if tile_type != -1:
				# In Godot 4, you need to convert your integer 'tile_type' 
				# into 'atlas_coords' (a Vector2i) for the given 'source_id'.
				# How you do this depends on how your TileSet is structured 
				# and what 'tile_type' represents.

				# Example: If 'tile_type' directly corresponds to the x-coordinate 
				# in your atlas, and all tiles are on the y-coordinate 0:
				# var atlas_coords = Vector2i(tile_type, 0) 
				
				# Example: If 'tile_type' is a flat index in an atlas of a known width:
				var atlas_width = 4 # Replace with your atlas's width in tiles
				var atlas_coords = Vector2i(tile_type % atlas_width, tile_type / atlas_width)

				if tile_map:
					tile_map.set_cell(layer_to_use, Vector2i(x, y), source_id_to_use, atlas_coords)
