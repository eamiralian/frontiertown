extends RefCounted

# Each entity has an id and a dictionary mapping component names to components.
var id: int = -1
var components: Dictionary = {}

func add_component(component_name: String, component) -> void:
	components[component_name] = component

func get_component(component_name: String):
	return components.get(component_name, null)

func update(tick: int) -> void:
	# The entity update can later be expanded to call component-specific behaviors.
	pass
