// Checks that diagnostic rendering is opt-in and leaves the simulation unchanged.
module sim

fn test_debug_view_is_opt_in_and_read_only() {
	mut simulation := new_simulation(SimulationConfig{
		enemy_capacity: 4
	})
	simulation.course = CourseProfile{
		slices: [CourseSlice{ left: 0.5, right: 5.5, rad: 21 }]
	}
	simulation.enemies[0] = Enemy{
		alive: true
		position: Vec2{ x: 2.8, y: 8 }
		kind: 0
	}
	before := simulation.checksum()
	assert simulation.render_debug_view_vertices(0, -2, 20, DebugViewOptions{}).len == 0
	border := simulation.render_debug_view_vertices(0, -2, 20, DebugViewOptions{
		boundaries: true
	})
	assert border.len > 0
	assert border.len % 2 == 0
	assert border.all(it.brightness == 2.95)
	all := simulation.render_debug_view_vertices(0, -2, 20, DebugViewOptions{
		boundaries: true
		slices: true
		enemies: true
		collisions: true
		exhaust: true
	})
	assert all.len > border.len
	assert all.any(it.brightness == 4.9)
	assert all.any(it.brightness == 6.9)
	assert simulation.checksum() == before
}
