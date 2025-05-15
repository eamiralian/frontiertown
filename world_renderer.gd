extends Node

# Import tile types from shared file
const TileTypes = preload("res://tile_types.gd")

signal initialized # Add this new signal

# A reference to the TileMap node in our scene (assumed to be set up in the editor)
var tile_map: TileMap
var ATLAS_WIDTH = 4
const TERRAIN_ATLAS_SOURCE_ID = 0
const CREATURE_ATLAS_SOURCE_ID = 1 # Assuming creature atlas is source_id 1
const TERRAIN_LAYER = 0 # Terrain on the bottom layer
const CREATURE_LAYER = 1 # Creatures on a layer above terrain
const DROPLET_LAYER = 2 # Layer for visualizing erosion droplets

# Heightmap visualization mode
var heightmap_mode: bool = false
var heightmap_shader_material: ShaderMaterial = null
var heightmap_image: Image = null
var heightmap_texture: ImageTexture = null
var heightmap_color_rect: ColorRect = null

const HEIGHTMAP_SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D heightmap : filter_nearest;  // Force nearest-neighbor filtering
uniform vec2 map_size;
uniform vec2 tile_size = vec2(32, 32); // Size of each tile in pixels
uniform int debug_mode = 0; // 0=normal, 1=raw height, 2=tile index, 3=color bands

void fragment() {
// Get the position in pixels
	vec2 pixel_pos = UV * vec2(textureSize(heightmap, 0)) * tile_size;
	
	// Calculate tile indices - each tile_size pixels is one tile
	ivec2 tile_index = ivec2(floor(pixel_pos / tile_size));
	
	// Ensure tile index is in valid range
	tile_index = clamp(tile_index, ivec2(0, 0), ivec2(map_size) - ivec2(1, 1));
	
	// Get the height value for this tile
	float height = texelFetch(heightmap, tile_index, 0).r;
	
	// Different visualization modes for debugging
	if (debug_mode == 1) {
		// Raw height visualization - show exact values
		COLOR = vec4(height, height, height, 1.0);
	} 
	else if (debug_mode == 2) {
		// Tile index visualization - shows if tile calculations are correct
		float norm_x = float(tile_index.x) / map_size.x;
		float norm_y = float(tile_index.y) / map_size.y;
		COLOR = vec4(norm_x, norm_y, 0.0, 1.0);
	}
	else {
		// Normal grayscale heightmap
		vec3 black = vec3(0.0, 0.0, 0.0);
		vec3 white = vec3(1.0, 1.0, 1.0);
		vec3 color = mix(black, white, clamp(height, 0.0, 1.0));
		COLOR = vec4(color, 1.0);
	}
}
"""

@export_group("Droplet Visualization")
@export var raindrop_tile_source_id: int = 0 # Set this to the source ID of your water tile in the TileSet (often 0 for the main atlas)
var raindrop_tile_atlas_coords = Vector2i(TileTypes.WATER_DROP % ATLAS_WIDTH, TileTypes.WATER_DROP / ATLAS_WIDTH)


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

# --- Heightmap Shader Setup ---
func _init_heightmap_shader():
	if not tile_map:
		return
	var shader = Shader.new()
	shader.code = HEIGHTMAP_SHADER_CODE
	heightmap_shader_material = ShaderMaterial.new()
	heightmap_shader_material.shader = shader

	# Set gradient colors (green to red by default, you can adjust)
	#heightmap_shader_material.set_shader_parameter("color_max", Color(0.0, 1.0, 0.0, 1.0))
	#heightmap_shader_material.set_shader_parameter("color_min", Color(1.0, 0.0, 0.0, 1.0))
	#heightmap_shader_material.set_shader_parameter("color_min", Color(0.0, 0.3, 1.0, 1.0)) # Blue (water)
	#heightmap_shader_material.set_shader_parameter("color_max", Color(0.9, 0.9, 0.9, 1.0)) # Light gray (rock/snow)

	# Create the heightmap image/texture
	var size = tile_map.get_used_rect().size
	heightmap_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
	# Fill image with zeros to initialize it properly
	heightmap_image.fill(Color(0, 0, 0, 1))
	heightmap_texture = ImageTexture.create_from_image(heightmap_image)
	heightmap_shader_material.set_shader_parameter("heightmap", heightmap_texture)
	heightmap_shader_material.set_shader_parameter("map_size", size)
	var tile_size = tile_map.tile_set.tile_size
	heightmap_shader_material.set_shader_parameter("tile_size", Vector2(tile_size.x, tile_size.y))

# Update the heightmap texture from world data
func update_heightmap_texture(world_data: Array):
	if not heightmap_image or not heightmap_texture:
		return
	for x in range(heightmap_image.get_width()):
		for y in range(heightmap_image.get_height()):
			var height = world_data[x][y]["height"]
			heightmap_image.set_pixel(x, y, Color(height, height, height, 1))
	heightmap_texture.update(heightmap_image)

# Callback when the Simulation Manager signals that the world is ready.
func _on_simulation_world_ready(world_data, generated_families) -> void:
	render_world(world_data, generated_families)

func render_world(world_data: Array, generated_families: Array) -> void:
	# Clear any existing tiles.
	if tile_map: # Good practice to check if tile_map is valid
		tile_map.clear_layer(TERRAIN_LAYER)
		tile_map.clear_layer(CREATURE_LAYER)
		#tile_map.clear_layer(DROPLET_LAYER) # Clear the droplet layer as well
	else:
		printerr("WorldRenderer: tile_map is null!")
		return

	for x in range(world_data.size()):
		for y in range(world_data[x].size()):
			var tile_info: Dictionary = world_data[x][y]
			var tile_type: int = _get_tile_type_for_height(tile_info.get("height", 0.0))
			if tile_type != -1:
				var atlas_coords = Vector2i(tile_type % ATLAS_WIDTH, tile_type / ATLAS_WIDTH)
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
		

func set_droplet_tile(tile_x: int, tile_y: int) -> void:
	if tile_map:
		tile_map.set_cell(DROPLET_LAYER, Vector2i(tile_x, tile_y), raindrop_tile_source_id, raindrop_tile_atlas_coords)
	else:
		printerr("WorldRenderer: TileMap node not found, cannot set droplet tile.")

func clear_entire_droplet_layer() -> void:
	if tile_map:
		tile_map.clear_layer(DROPLET_LAYER)
	else:
		printerr("WorldRenderer: TileMap node not found, cannot clear droplet layer.")

var heightmap_initialized: bool = false		
func set_heightmap_mode(enabled: bool, world_data) -> void:
	heightmap_mode = enabled
	print("WorldRenderer: Heightmap visualization mode ", "enabled" if enabled else "disabled")
	
	# Create ColorRect on demand if it doesn't exist
	if enabled:
		if not heightmap_initialized:
			_init_heightmap_shader()
			heightmap_initialized = true
			if not heightmap_color_rect:
				heightmap_color_rect = ColorRect.new()
				add_child(heightmap_color_rect)
				# Position it to cover the tile map exactly
				var map_rect = tile_map.get_used_rect()
				var tile_size = tile_map.tile_set.tile_size
				heightmap_color_rect.size = Vector2(map_rect.size.x * tile_size.x, map_rect.size.y * tile_size.y)
				heightmap_color_rect.position = Vector2(map_rect.position.x * tile_size.x, map_rect.position.y * tile_size.y)
				print("Created heightmap overlay at position ", heightmap_color_rect.position, " with size ", heightmap_color_rect.size)
			
			# Apply shader material to ColorRect
			heightmap_color_rect.material = heightmap_shader_material
		heightmap_color_rect.show()
	else:
		# Hide the color rect when heightmap mode is off
		if heightmap_color_rect:
			heightmap_color_rect.hide()
		
# Helper function to determine tile type based on height value
# This should match the logic in world_generator.gd's _get_tile_type_for_height function
func _get_tile_type_for_height(height_val: float) -> int:
	# These should match the logic in world_generator.gd
	const WATER_LEVEL = 0.07
	const DIRT_LEVEL = 0.2
	const GRASS_LEVEL = 0.75
	
	if height_val < WATER_LEVEL:
		return TileTypes.TILE_WATER
	elif height_val < DIRT_LEVEL:
		return TileTypes.TILE_DIRT
	elif height_val < GRASS_LEVEL:
		return TileTypes.TILE_GRASS
	else:
		return TileTypes.TILE_ROCK

func center_camera_on_map() -> void:
	var camera = get_viewport().get_camera_2d()
	if camera:
		var map_rect = tile_map.get_used_rect()
		var tile_size = tile_map.tile_set.tile_size
		
		# Calculate center position in world coordinates
		var center_x = (map_rect.position.x + map_rect.size.x / 2) * tile_size.x
		var center_y = (map_rect.position.y + map_rect.size.y / 2) * tile_size.y
		var center_pos = Vector2(center_x, center_y)
		
		# Set camera position
		camera.global_position = center_pos
		print("Camera centered at position: ", center_pos)
	else:
		printerr("WorldRenderer: Could not find Camera2D to center on map")
