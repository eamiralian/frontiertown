# Creature.gd
extends RefCounted

# Data for our creature (family member)
var creature_id: int = -1
var display_name: String = ""
var age: int = 0
var gender: String = ""
var map_pos_x: int = -1
var map_pos_y: int = -1
var relationships: Array = []  # This will store IDs or references to related creatures.
