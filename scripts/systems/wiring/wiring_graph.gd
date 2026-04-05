extends RefCounted

# Generic graph traversal helpers shared by network and electrical wiring overlays.
static func has_path(start_node, end_node, get_neighbors: Callable) -> bool:
	if start_node == null or end_node == null:
		return false
	if not get_neighbors.is_valid():
		return false

	var visited := {}
	var queue: Array = [start_node]

	while queue.size() > 0:
		var current = queue.pop_front()
		if current == null:
			continue
		if visited.has(current):
			continue

		visited[current] = true
		if current == end_node:
			return true

		var neighbors_result: Variant = get_neighbors.call(current)
		if not (neighbors_result is Array):
			continue

		for neighbor in neighbors_result:
			if neighbor == null:
				continue
			if not visited.has(neighbor):
				queue.append(neighbor)

	return false

static func neighbors_from_edge_list(current_node, edges: Array, start_key: StringName = &"start_connector", end_key: StringName = &"end_connector") -> Array:
	var neighbors: Array = []
	for edge in edges:
		if not (edge is Dictionary):
			continue
		var start_node: Variant = edge.get(start_key, null)
		var end_node: Variant = edge.get(end_key, null)
		if start_node == null or end_node == null:
			continue

		if start_node == current_node and end_node != null and not neighbors.has(end_node):
			neighbors.append(end_node)
		elif end_node == current_node and start_node != null and not neighbors.has(start_node):
			neighbors.append(start_node)

	return neighbors

static func neighbors_from_segment_connections(current_node) -> Array:
	var neighbors: Array = []
	if current_node == null:
		return neighbors

	var segments: Variant = current_node.get("connected_segments")
	if not (segments is Array):
		return neighbors

	for segment in segments:
		if segment == null:
			continue
		if not segment.has_method("get_other_point"):
			continue
		var next_node = segment.get_other_point(current_node)
		if next_node != null and not neighbors.has(next_node):
			neighbors.append(next_node)

	return neighbors

static func collect_anchor_chain_route(clicked_edge, start_node, end_node, is_anchor: Callable, get_connected_edges: Callable, get_other_node: Callable, max_steps: int = 128) -> Array:
	var route: Array = []
	if clicked_edge == null:
		return route

	route.append(clicked_edge)
	_append_anchor_chain(route, start_node, clicked_edge, is_anchor, get_connected_edges, get_other_node, max_steps)
	_append_anchor_chain(route, end_node, clicked_edge, is_anchor, get_connected_edges, get_other_node, max_steps)
	return route

static func _append_anchor_chain(route: Array, start_node, incoming_edge, is_anchor: Callable, get_connected_edges: Callable, get_other_node: Callable, max_steps: int) -> void:
	if start_node == null or incoming_edge == null:
		return

	var current_node = start_node
	var previous_edge = incoming_edge
	var safety := 0

	while current_node != null and safety < max_steps:
		safety += 1
		if not is_anchor.call(current_node):
			return

		var connected_edges: Variant = get_connected_edges.call(current_node)
		if not (connected_edges is Array):
			return

		var next_edge = null
		for edge in connected_edges:
			if edge == null:
				continue
			if edge == previous_edge:
				continue
			next_edge = edge
			break

		if next_edge == null:
			return

		if not route.has(next_edge):
			route.append(next_edge)

		var next_node = get_other_node.call(next_edge, current_node)
		if next_node == null:
			return

		previous_edge = next_edge
		current_node = next_node
