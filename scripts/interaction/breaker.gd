extends InteractableObject

@export var max_electrical_connections: int = 4
@export var electrical_node_offset: Vector2 = Vector2(0, 34)
@export var internet_node_offset: Vector2 = Vector2(28, 34)

var electrical_node: Node2D = null
var internet_node: Node2D = null
var electrical_connected_segments: Array = []
var network_connected_segments: Array = []
var port_label: Label = null
var network_node_type := "internet_source"

var sprites = {
	"front": preload("res://assets/object_sprites/breaker/breaker_front.png"),
	"right": preload("res://assets/object_sprites/breaker/breaker_right.png"),
	"back": preload("res://assets/object_sprites/breaker/breaker_back.png"),
	"left": preload("res://assets/object_sprites/breaker/breaker_left.png")
}

func _ready() -> void:
	add_to_group("electrical_connectable")
	add_to_group("network_nodes")
	object_name = "Breaker"
	actions = ["Turn Off", "Turn On"]
	interaction_range = 150.0
	super._ready()
	_ensure_electrical_node()
	_ensure_internet_node()
	_ensure_port_label()
	_update_port_label()

func set_facing(direction: String) -> void:
	apply_facing_rotation(direction)
	if sprites.has(direction):
		sprite.texture = sprites[direction]
	_update_electrical_node_position()
	_update_internet_node_position()

func perform_action(action_name: String) -> void:
	match action_name:
		"Turn Off":
			turn_off()
		"Turn On":
			turn_on()
		"Reboot":
			reboot()

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func reboot() -> void:
	pass

func get_electrical_nodes() -> Array[Node2D]:
	_ensure_electrical_node()
	var nodes: Array[Node2D] = []
	if is_instance_valid(electrical_node):
		nodes.append(electrical_node)
	return nodes

func can_accept_electrical_connection(connector_node: Node2D, current_connection_count: int = -1) -> bool:
	_ensure_electrical_node()
	if connector_node == null or connector_node != electrical_node:
		return false

	var connection_count: int = current_connection_count
	if connection_count < 0:
		connection_count = electrical_connected_segments.size()

	return connection_count < get_port_limit()

func add_connection(segment) -> void:
	add_connection_for_node(segment, internet_node)

func remove_connection(segment) -> void:
	remove_connection_for_node(segment, internet_node)

func add_connection_for_node(segment, connector_node: Node2D) -> void:
	_ensure_internet_node()
	if connector_node != internet_node:
		return
	if not network_connected_segments.has(segment):
		network_connected_segments.append(segment)

func remove_connection_for_node(segment, connector_node: Node2D) -> void:
	_ensure_internet_node()
	if connector_node != internet_node:
		return
	network_connected_segments.erase(segment)

func add_electrical_connection(connection_target) -> void:
	if not electrical_connected_segments.has(connection_target):
		electrical_connected_segments.append(connection_target)
		_update_port_label()

func remove_electrical_connection(connection_target) -> void:
	electrical_connected_segments.erase(connection_target)
	_update_port_label()

func get_network_nodes() -> Array[Node2D]:
	_ensure_internet_node()
	var nodes: Array[Node2D] = []
	if is_instance_valid(internet_node):
		nodes.append(internet_node)
	return nodes

func can_accept_network_connection(connector_node: Node2D, remote_owner: Node = null, remote_connector: Node2D = null, current_connection_count: int = -1) -> bool:
	_ensure_internet_node()
	if connector_node == null or connector_node != internet_node:
		return false

	var connection_count: int = current_connection_count
	if connection_count < 0:
		connection_count = network_connected_segments.size()

	# Allow selecting this node as a wire start endpoint before the remote is chosen.
	if remote_owner == null:
		return connection_count < 1

	if not remote_owner.has_method("get_network_port_type"):
		return false
	var remote_type: String = str(remote_owner.call("get_network_port_type", remote_connector))
	if remote_type != "internet":
		return false
	return connection_count < 1

func get_network_port_type(connector_node: Node2D) -> String:
	_ensure_internet_node()
	if connector_node == internet_node:
		return "internet_source"
	return ""

func get_network_port_icon(connector_node: Node2D) -> String:
	if get_network_port_type(connector_node) == "internet_source":
		return "🌐"
	return ""

func get_electrical_port_icon(connector_node: Node2D) -> String:
	_ensure_electrical_node()
	if connector_node == electrical_node:
		return "⚡"
	return ""

func has_free_port() -> bool:
	return electrical_connected_segments.size() < get_port_limit()

func get_port_limit() -> int:
	return max(0, max_electrical_connections)

func is_electrical_power_source() -> bool:
	return true

func set_port_label_visible(show_label: bool) -> void:
	_ensure_port_label()
	if port_label != null:
		port_label.visible = show_label

func _ensure_electrical_node() -> void:
	electrical_node = get_node_or_null("ElectricalNode") as Node2D
	if electrical_node == null:
		electrical_node = Node2D.new()
		electrical_node.name = "ElectricalNode"
		add_child(electrical_node)

	_update_electrical_node_position()

func _ensure_internet_node() -> void:
	internet_node = get_node_or_null("InternetNode") as Node2D
	if internet_node == null:
		internet_node = Node2D.new()
		internet_node.name = "InternetNode"
		add_child(internet_node)

	_update_internet_node_position()

func _update_electrical_node_position() -> void:
	if electrical_node == null:
		return
	electrical_node.position = electrical_node_offset

func _update_internet_node_position() -> void:
	if internet_node == null:
		return
	internet_node.position = internet_node_offset

func _ensure_port_label() -> void:
	if port_label != null and is_instance_valid(port_label):
		return

	port_label = get_node_or_null("PortLabel") as Label
	if port_label == null:
		port_label = Label.new()
		port_label.name = "PortLabel"
		port_label.position = Vector2(-26, -52)
		port_label.size = Vector2(72, 28)
		port_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		port_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		port_label.z_index = 20
		port_label.add_theme_font_size_override("font_size", 18)
		port_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 1.0))
		port_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 1.0))
		port_label.add_theme_constant_override("outline_size", 3)
		port_label.visible = false
		add_child(port_label)

func _update_port_label() -> void:
	_ensure_port_label()
	if port_label == null:
		return

	port_label.text = "%d/%d" % [electrical_connected_segments.size(), get_port_limit()]
