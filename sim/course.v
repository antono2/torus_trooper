// Generates course slices, tunnel profiles and level-dependent course colors.
module sim

import math

struct CourseState {
mut:
	rad          f32 = 21
	point_count  int = 24
	course_width f32 = 24
	curve        f32
	turn_x       f32
	turn_y       f32
}

pub struct CourseSlice {
pub:
	left   f32
	right  f32
	rad    f32
	full   bool
	turn_x f32
	turn_y f32
}

pub struct CourseRing {
pub:
	index    int
	is_final bool
}

pub struct CourseProfile {
pub:
	slices []CourseSlice
	rings  []CourseRing
}

fn tunnel_palette_index(level f32) int {
	return int(level) - 1
}

pub fn (simulation &Simulation) tunnel_line_color() RgbColor {
	index := tunnel_palette_index(simulation.level)
	current := tunnel_line_palette(index)
	if simulation.zone % 2 == 1 && simulation.palette_transition_ticks > 0 {
		previous := tunnel_line_palette(index + 6)
		ratio := f32(simulation.palette_transition_ticks) / palette_transition_duration_ticks
		return RgbColor{
			r: previous.r * ratio + current.r * (1 - ratio)
			g: previous.g * ratio + current.g * (1 - ratio)
			b: previous.b * ratio + current.b * (1 - ratio)
		}
	}
	return current
}

pub fn (simulation &Simulation) tunnel_poly_color() RgbColor {
	index := tunnel_palette_index(simulation.level)
	current := tunnel_poly_palette(index)
	if simulation.zone % 2 == 1 && simulation.palette_transition_ticks > 0 {
		previous := tunnel_poly_palette(index + 6)
		ratio := f32(simulation.palette_transition_ticks) / palette_transition_duration_ticks
		return RgbColor{
			r: previous.r * ratio + current.r * (1 - ratio)
			g: previous.g * ratio + current.g * (1 - ratio)
			b: previous.b * ratio + current.b * (1 - ratio)
		}
	}
	return current
}

pub fn (simulation &Simulation) tunnel_dark_line_ratio() f32 {
	transition := clamp_f32(f32(simulation.palette_transition_ticks) / palette_transition_duration_ticks, 0, 1)
	return if simulation.zone % 2 == 1 { transition } else { 1 - transition }
}

fn tunnel_slice_brightness(slice_count int, dark_ratio f32) ([]f32, []f32) {
	mut lines := []f32{len: slice_count}
	mut lights := []f32{len: slice_count}
	mut line_brightness := f32(0.4)
	mut light_brightness := 0.5 - dark_ratio * 0.2
	mut index := slice_count - 1
	for index >= 1 {
		lines[index] = line_brightness
		lights[index] = light_brightness
		line_brightness = clamp_f32(line_brightness * 1.02, 0, 1)
		light_brightness = clamp_f32(light_brightness * 1.02, 0, 1)
		if index < slice_count * 3 / 4 {
			line_brightness *= 1 - dark_ratio * 0.05
			light_brightness *= 1 + dark_ratio * 0.02
		}
		index--
	}
	if slice_count > 0 {
		lines[0] = line_brightness
		lights[0] = light_brightness
	}
	// Fixed-function wide lines stayed equally heavy at the vanishing point.
	// Fade coverage continuously with distance so the mesh reads progressively
	// thinner and the final ring disappears instead of forming a bright cap.
	if slice_count > 1 {
		for ring in 0 .. slice_count {
			remaining := 1 - f32(ring) / f32(slice_count - 1)
			// Fixed-width Vulkan lines accumulate heavily near the vanishing
			// point. A cubic luminance/coverage taper counters that density so
			// the apparent stroke becomes thin before the last ring vanishes.
			coverage := remaining * remaining * remaining
			lines[ring] *= coverage
			lights[ring] *= coverage
		}
	}
	return lines, lights
}

fn tunnel_poly_brightness(slice_count int, panel_ring_count int) []f32 {
	mut result := []f32{len: slice_count}
	mut brightness := f32(0)
	mut index := slice_count - 1
	for index >= 1 {
		result[index] = brightness
		if index < panel_ring_count {
			if brightness <= 0 {
				brightness = 0.2
			}
			brightness = clamp_f32(brightness * 1.03, 0, 1)
		}
		index--
	}
	// The first panel used to appear at 20% opacity in a single slice. At
	// the far end of the tunnel that slice barely moves on screen, so the
	// panel seemed to blink before it started advancing toward the camera.
	// Fade the physical rows in over five slices instead.
	first_visible := int_min(slice_count - 2, panel_ring_count - 2)
	for ring in 0 .. slice_count {
		if result[ring] <= 0 {
			continue
		}
		progress := clamp_f32(f32(first_visible - ring + 1) / 5, 0, 1)
		result[ring] *= progress * progress * (3 - 2 * progress)
	}
	return result
}

fn sampled_course_brightness(values []f32, index f32) f32 {
	if values.len == 0 {
		return 0
	}
	clamped := clamp_f32(index, 0, f32(values.len - 1))
	low := int(math.floor(f64(clamped)))
	high := int_min(low + 1, values.len - 1)
	ratio := clamped - f32(low)
	return values[low] * (1 - ratio) + values[high] * ratio
}

struct CoursePart {
	start  int
	length int
	state  CourseState
}

pub fn generate_course(seed u32) CourseProfile {
	mut rng := new_mt19937(seed)
	mut parts := []CoursePart{}
	mut previous := CourseState{}
	mut length := 0
	for length < 5000 {
		part_length := 64 + rng.next_int(30)
		mut state := previous
		state.turn_x = rng.next_signed_f32(0.005)
		state.turn_y = rng.next_signed_f32(0.005)
		if f32(math.abs(previous.curve)) >= 1 {
			if rng.next_int(2) == 0 {
				state.curve = (0.1 + rng.next_f32(0.04)) * if previous.curve >= 1 {
					f32(-1)
				} else {
					f32(1)
				}
			} else {
				state.curve = 0
			}
		} else if previous.course_width == f32(previous.point_count) || rng.next_int(2) == 0 {
			match rng.next_int(3) {
				0 {
					state.rad = 21 + rng.next_signed_f32(21 * 0.3)
					old_count := state.point_count
					state.point_count = int(state.rad * 24 / 21)
					if previous.course_width == f32(old_count) {
						state.course_width = f32(state.point_count)
					} else {
						state.course_width = previous.course_width * f32(state.point_count) / f32(old_count)
					}
				}
				1 {
					state.course_width = f32(rng.next_int(state.point_count / 4)) + f32(state.point_count) * 0.36
				}
				else {
					state.course_width = f32(state.point_count)
				}
			}
		} else {
			match rng.next_int(4) {
				0 {
					state.curve = (0.1 + rng.next_f32(0.04)) * if rng.next_int(2) == 0 {
						f32(-1)
					} else {
						f32(1)
					}
				}
				2 {
					state.curve = 0.04 + rng.next_f32(0.05)
					if rng.next_int(2) == 0 {
						state.curve = -state.curve
					}
				}
				else {
					state.curve = 0
				}
			}
		}
		parts << CoursePart{ start: length, length: part_length, state: state }
		length += part_length
		previous = state
	}
	parts[0] = CoursePart{ ...parts[0], state: CourseState{} }
	parts[parts.len - 1] = CoursePart{ ...parts[parts.len - 1], state: CourseState{} }
	mut slices := []CourseSlice{cap: length}
	mut point_from := f32(0)
	mut part_index := 0
	for index in 0 .. length {
		for index >= parts[part_index].start + parts[part_index].length {
			part_index++
		}
		part := parts[part_index]
		previous_index := if part_index == 0 { parts.len - 1 } else { part_index - 1 }
		ratio := clamp_f32(f32(index - part.start) / 64, 0, 1)
		state := blend_course_state(part.state, parts[previous_index].state, ratio)
		left := wrap_angle(point_from * f32(math.pi * 2) / f32(state.point_count))
		right := wrap_angle((point_from + state.course_width) * f32(math.pi * 2) / f32(state.point_count))
		slices << CourseSlice{
			left:   left
			right:  right
			rad:    state.rad
			full:   state.course_width >= f32(state.point_count - 1)
			turn_x: state.turn_x
			turn_y: state.turn_y
		}
		point_from += state.curve
		for point_from >= f32(state.point_count) {
			point_from -= f32(state.point_count)
		}
		for point_from < 0 {
			point_from += f32(state.point_count)
		}
	}
	mut rings := []CourseRing{}
	mut ring_index := 5
	for ring_index < length - 100 {
		rings << CourseRing{
			index:    ring_index
			is_final: ring_index == 5
		}
		ring_index += 100 + rng.next_int(200)
	}
	return CourseProfile{
		slices: slices
		rings:  rings
	}
}

fn blend_course_state(current CourseState, previous CourseState, ratio f32) CourseState {
	point_count := int(f32(current.point_count) * ratio + f32(previous.point_count) * (1 - ratio))
	width := if current.course_width == f32(current.point_count)
		&& previous.course_width == f32(previous.point_count) {
		f32(point_count)
	} else {
		current.course_width * ratio + previous.course_width * (1 - ratio)
	}
	return CourseState{
		rad:          current.rad * ratio + previous.rad * (1 - ratio)
		point_count:  point_count
		course_width: width
		curve:        current.curve
		turn_x:       current.turn_x * ratio + previous.turn_x * (1 - ratio)
		turn_y:       current.turn_y * ratio + previous.turn_y * (1 - ratio)
	}
}

pub fn (course &CourseProfile) slice_at(position f32) CourseSlice {
	if course.slices.len == 0 {
		return CourseSlice{ full: true, rad: 21 }
	}
	mut index := int(position) % course.slices.len
	if index < 0 {
		index += course.slices.len
	}
	return course.slices[index]
}

pub fn course_side(angle f32, slice CourseSlice) int {
	if slice.full {
		return 0
	}
	if slice.right <= slice.left {
		if angle > slice.right && angle < slice.left {
			return if angle < (slice.right + slice.left) / 2 { 1 } else { -1 }
		}
		return 0
	}
	if angle >= slice.left && angle <= slice.right {
		return 0
	}
	center_opposite := wrap_angle((slice.left + slice.right) / 2 + f32(math.pi))
	if center_opposite >= f32(math.pi) {
		return if angle < center_opposite && angle > slice.right { 1 } else { -1 }
	}
	return if angle > center_opposite && angle < slice.left { -1 } else { 1 }
}

pub struct CourseVertex {
pub:
	x          f32
	y          f32
	z          f32
	brightness f32
}

pub struct CourseFillVertex {
pub:
	x f32
	y f32
	z f32
	r f32
	g f32
	b f32
	a f32
}

const course_normal_ring_brightness_base = f32(2)
const course_final_ring_brightness_base = f32(4)
const course_side_light_brightness_base = f32(6)
const course_render_depth_base = f32(2.2)
const course_render_depth_scale = f32(0.55)
const course_render_radius = f32(1.35)
const course_render_height_scale = course_render_radius / 21
// A source tunnel slice advances five OpenGL world units. Model-local Z uses
// that longitudinal world scale, independently from the radial 21-unit scale.
const source_tunnel_slice_depth = f32(5)
const course_render_longitudinal_scale = course_render_depth_scale / source_tunnel_slice_depth
const source_tunnel_radius_ratio = f32(1.05)
const course_render_camera_distance = -course_render_depth_base / course_render_depth_scale
// Retain one complete tile plus half a tile of clipping guard behind the
// camera. Recycling at exactly one tile could discard the whole object while
// rasterization still covered its camera-crossing edge, producing a flash.
const course_render_rear_margin = f32(1.5)
// Legacy snapshot helpers retain three quarters of the sampled course. The
// runtime can request a longer solid-panel horizon, while boundary markers
// continue to the last complete sampled ring.
const course_panel_ring_numerator = 3
const course_panel_ring_denominator = 4
const ship_render_depth_offset = f32(-0.3)
const ship_render_surface_clearance = f32(0.145)
// The source exhaust starts only 0.15 course units behind the ship, but the
// high-resolution player silhouette needs more visible clearance. Keep the
// simulation spawn unchanged and move only
// the rendered plume far enough back for its narrow tip to clear the hull.
const ship_exhaust_render_depth_clearance = f32(0.42)
const course_orientation_angular_sample = f32(0.02)
const course_orientation_radial_sample = f32(0.1)

struct CourseRenderFrame {
mut:
	distance         f32
	center_x         f32
	center_y         f32
	heading_x        f32
	heading_y        f32
	radius           f32
	light_brightness f32
	slice            CourseSlice
}

struct CourseAngleSpan {
	start f32
	end   f32
}

struct CourseUnitPoint {
	angle  f32
	sine   f32
	cosine f32
}

fn course_unit_point(angle f32, camera_angle f32) CourseUnitPoint {
	view_angle := angle - camera_angle
	return CourseUnitPoint{
		angle: angle
		sine: f32(math.sin(view_angle))
		cosine: f32(math.cos(view_angle))
	}
}

fn course_segment_points(segment_count int, camera_angle f32) []CourseUnitPoint {
	mut points := []CourseUnitPoint{len: segment_count + 1}
	for segment in 0 .. segment_count + 1 {
		angle := f32(segment) / f32(segment_count) * f32(math.pi * 2)
		points[segment] = course_unit_point(angle, camera_angle)
	}
	return points
}

fn course_surface_xy_from_unit(frame CourseRenderFrame, point CourseUnitPoint) (f32, f32) {
	return frame.center_x - point.sine * frame.radius, frame.center_y + point.cosine * frame.radius
}

fn course_surface_xy(frame CourseRenderFrame, angle f32, camera_angle f32) (f32, f32) {
	return course_surface_xy_from_unit(frame, course_unit_point(angle, camera_angle))
}

fn course_render_phase(position f32) f32 {
	return position - f32(math.floor(position))
}

fn course_render_start_distance(position f32) f32 {
	return course_render_start_distance_for_view(position, course_render_camera_distance, 1)
}

fn course_render_start_distance_for_view(position f32, camera_distance f32,
	view_direction f32) f32 {
	// Keep the mesh seam more than a complete tile behind the actual camera.
	// Snap it to the half-slice lattice so recycling happens only where it cannot
	// be seen, while the visible panels continue moving smoothly through it.
	phase := course_render_phase(position)
	direction := if view_direction < 0 { f32(-1) } else { f32(1) }
	behind := camera_distance - direction * course_render_rear_margin
	lattice := phase + behind - 0.5
	snapped := if direction > 0 {
		f32(math.floor(f64(lattice)))
	} else {
		f32(math.ceil(f64(lattice)))
	}
	return snapped + 0.5 - phase
}

// course_render_start_for_camera converts the active shader camera into course
// distance. The 3D replay camera stores its eye position directly; gameplay's
// 2D projection stores the inverse eye offset. In both cases the returned seam
// is guarded behind the direction in which the camera is looking.
pub fn (simulation &Simulation) course_render_start_for_camera(camera_depth f32,
	use_3d_camera bool, view_direction f32) f32 {
	camera_distance := simulation.course_camera_distance(camera_depth, use_3d_camera)
	return course_render_start_distance_for_view(simulation.ship.course_position, camera_distance, view_direction)
}

pub fn (simulation &Simulation) course_camera_distance(camera_depth f32,
	use_3d_camera bool) f32 {
	return course_render_camera_distance + if use_3d_camera {
		camera_depth
	} else {
		-camera_depth
	}
}

pub fn (simulation &Simulation) ship_surface_radius() f32 {
	return simulation.actor_surface_radius_at(simulation.ship.relative_depth)
}

pub fn (simulation &Simulation) ship_render_surface_radius(camera_angle f32) f32 {
	_, radius := simulation.actor_surface_placement_with_offset(simulation.ship.angle, simulation.ship.relative_depth + ship_render_depth_offset, camera_angle, -ship_render_surface_clearance)
	return radius
}

pub fn (simulation &Simulation) ship_render_depth() f32 {
	return simulation.ship.relative_depth + ship_render_depth_offset
}

fn (simulation &Simulation) actor_surface_radius_at(relative_depth f32) f32 {
	slice := simulation.course.slice_at(simulation.ship.course_position + relative_depth)
	return course_render_radius * slice.rad / 21 / source_tunnel_radius_ratio
}

fn (simulation &Simulation) advance_course_frame(frame CourseRenderFrame,
	target_distance f32) CourseRenderFrame {
	mut result := frame
	// Keep the integration cursor in f64 even though the render snapshot is f32.
	// Near a slice boundary, the remaining step can be smaller than one f32 ULP
	// at a distant rear ring. Updating result.distance directly would then make no
	// progress and freeze the title replay inside this loop.
	mut current_distance := f64(result.distance)
	target := f64(target_distance)
	for math.abs(target - current_distance) > 0.000001 {
		direction := if target > current_distance { f64(1) } else { f64(-1) }
		absolute_position := f64(simulation.ship.course_position) + current_distance
		floor_position := math.floor(absolute_position)
		fraction := absolute_position - floor_position
		mut boundary_distance := if direction > 0 { 1 - fraction } else { fraction }
		if boundary_distance < 0.000000001 {
			boundary_distance = 1
		}
		remaining := math.abs(target - current_distance)
		step64 := direction * f64_min(remaining, boundary_distance)
		step := f32(step64)
		// A midpoint sample and trapezoidal heading integration keep the path
		// continuous while crossing a discrete source tunnel slice boundary.
		slice := simulation.course.slice_at(f32(absolute_position + step64 * 0.5))
		result.center_x += (result.heading_x + slice.turn_x * step * 0.5) * course_render_depth_scale * step
		result.center_y += (result.heading_y + slice.turn_y * step * 0.5) * course_render_depth_scale * step
		result.heading_x += slice.turn_x * step
		result.heading_y += slice.turn_y * step
		current_distance += step64
	}
	result.distance = target_distance
	result.slice = simulation.course.slice_at(simulation.ship.course_position + target_distance)
	result.radius = course_render_radius * result.slice.rad / 21
	return result
}

fn (simulation &Simulation) course_frame_at(relative_depth f32) CourseRenderFrame {
	return simulation.advance_course_frame(CourseRenderFrame{}, relative_depth)
}

// actor_course_frame_at samples the same ship-anchored accumulated bend used by
// the tunnel. The camera remains behind that origin. Actors therefore stay on a
// physical slice as its render-buffer index changes at a fractional wrap.
fn (simulation &Simulation) actor_course_frame_at(relative_depth f32) CourseRenderFrame {
	frame := simulation.course_frame_at(relative_depth)
	return CourseRenderFrame{
		...frame
		radius: frame.radius / source_tunnel_radius_ratio
	}
}

fn (simulation &Simulation) actor_surface_placement(angle f32, relative_depth f32,
	camera_angle f32) (f32, f32) {
	return simulation.actor_surface_placement_with_offset(angle, relative_depth, camera_angle, 0)
}

fn (simulation &Simulation) actor_surface_placement_with_offset(angle f32, relative_depth f32,
	camera_angle f32, radial_offset f32) (f32, f32) {
	mut frame := simulation.actor_course_frame_at(relative_depth)
	frame = CourseRenderFrame{ ...frame, radius: frame.radius + radial_offset }
	x, y := course_surface_xy(frame, angle, camera_angle)
	radius := f32(math.sqrt(f64(x * x + y * y)))
	view_angle := f32(math.atan2(f64(y), f64(x)))
	return wrap_angle(view_angle + camera_angle - f32(math.pi / 2)), radius
}

// actor_surface_render_pose returns the current polar placement plus three
// nearby points in the tunnel-local frame: forward along the course, around
// the circumference and radially outward. Model transforms rotate objects
// in this 3D frame. Keeping all three projected
// directions prevents a bank from being mistaken for an in-plane turn.
fn (simulation &Simulation) actor_surface_render_pose(angle f32, relative_depth f32,
	camera_angle f32, radial_offset f32) (f32, f32, f32, f32, f32, f32, f32, f32) {
	mut frame := simulation.course_frame_at(relative_depth)
	mut tangent_frame := simulation.advance_course_frame(frame, relative_depth + 0.5)
	frame.radius = frame.radius / source_tunnel_radius_ratio + radial_offset
	tangent_frame.radius = tangent_frame.radius / source_tunnel_radius_ratio + radial_offset
	mut normal_frame := frame
	normal_frame.radius += course_orientation_radial_sample
	x, y := course_surface_xy(frame, angle, camera_angle)
	tangent_x, tangent_y := course_surface_xy(tangent_frame, angle, camera_angle)
	lateral_x, lateral_y := course_surface_xy(frame, angle + course_orientation_angular_sample, camera_angle)
	normal_x, normal_y := course_surface_xy(normal_frame, angle, camera_angle)
	radius := f32(math.sqrt(f64(x * x + y * y)))
	tangent_radius := f32(math.sqrt(f64(tangent_x * tangent_x + tangent_y * tangent_y)))
	lateral_radius := f32(math.sqrt(f64(lateral_x * lateral_x + lateral_y * lateral_y)))
	normal_radius := f32(math.sqrt(f64(normal_x * normal_x + normal_y * normal_y)))
	view_angle := f32(math.atan2(f64(y), f64(x)))
	tangent_view_angle := f32(math.atan2(f64(tangent_y), f64(tangent_x)))
	lateral_view_angle := f32(math.atan2(f64(lateral_y), f64(lateral_x)))
	normal_view_angle := f32(math.atan2(f64(normal_y), f64(normal_x)))
	polar_angle := wrap_angle(view_angle + camera_angle - f32(math.pi / 2))
	tangent_angle := wrap_angle(tangent_view_angle + camera_angle - f32(math.pi / 2))
	lateral_angle := wrap_angle(lateral_view_angle + camera_angle - f32(math.pi / 2))
	normal_angle := wrap_angle(normal_view_angle + camera_angle - f32(math.pi / 2))
	return polar_angle, radius, tangent_angle, tangent_radius, lateral_angle, lateral_radius, normal_angle, normal_radius
}

fn append_course_angle_overlap(mut spans []CourseAngleSpan, segment_start f32,
	segment_end f32, playable_start f32, playable_end f32) {
	start := if segment_start > playable_start { segment_start } else { playable_start }
	end := if segment_end < playable_end { segment_end } else { playable_end }
	if end > start {
		spans << CourseAngleSpan{ start: start, end: end }
	}
}

// playable_course_angle_spans clips a tessellation segment against the same
// continuous angular interval used by ship collision. This prevents the filled
// surface from making either edge appear wider or narrower by half a segment.
fn playable_course_angle_spans(segment_start f32, segment_end f32,
	slice CourseSlice) []CourseAngleSpan {
	if slice.full {
		return [CourseAngleSpan{ start: segment_start, end: segment_end }]
	}
	mut spans := []CourseAngleSpan{cap: 2}
	if slice.right > slice.left {
		append_course_angle_overlap(mut spans, segment_start, segment_end, slice.left, slice.right)
	} else {
		append_course_angle_overlap(mut spans, segment_start, segment_end, 0, slice.right)
		append_course_angle_overlap(mut spans, segment_start, segment_end, slice.left, f32(math.pi * 2))
	}
	return spans
}

// render_course_vertices flattens the visible course into x/y/z/brightness
// line vertices. The buffer is deliberately backend-neutral for Vulkan today
// and a future OpenCL geometry stage.
pub fn (simulation &Simulation) render_course_vertices(ring_count int, segment_count int) []f32 {
	return simulation.render_course_vertices_for_camera(ring_count, segment_count, simulation.camera_angle())
}

pub fn (simulation &Simulation) render_course_vertices_for_camera(ring_count int, segment_count int,
	camera_angle f32) []f32 {
	snapshot := simulation.render_course_snapshot(ring_count, segment_count, camera_angle)
	mut values := []f32{cap: snapshot.len * 4}
	for vertex in snapshot {
		values << vertex.x
		values << vertex.y
		values << vertex.z
		values << vertex.brightness
	}
	return values
}

pub fn (simulation &Simulation) render_course_snapshot(ring_count int, segment_count int,
	camera_angle f32) []CourseVertex {
	return simulation.render_course_snapshot_from(ring_count, segment_count, camera_angle, course_render_start_distance(simulation.ship.course_position))
}

pub fn (simulation &Simulation) render_course_snapshot_from(ring_count int, segment_count int,
	camera_angle f32, start_distance f32) []CourseVertex {
	return simulation.render_course_snapshot_from_with_panel_horizon(ring_count, segment_count, camera_angle, start_distance, 0)
}

pub fn (simulation &Simulation) render_course_snapshot_from_with_panel_horizon(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int) []CourseVertex {
	return simulation.render_course_snapshot_with_rear_blend(ring_count, segment_count, camera_angle, start_distance, panel_count, 0, 0, false, true)
}

pub fn (simulation &Simulation) render_course_snapshot_from_with_rear_blend(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int,
	camera_distance f32, blend_percent int) []CourseVertex {
	return simulation.render_course_snapshot_with_rear_blend(ring_count, segment_count, camera_angle, start_distance, panel_count, camera_distance, blend_percent, false, true)
}

// Runtime settings specify a physical slice horizon, so the last sampled
// wire ring must land exactly on that depth plane.
pub fn (simulation &Simulation) render_course_snapshot_from_with_draw_distance(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int,
	camera_distance f32, blend_percent int) []CourseVertex {
	return simulation.render_course_snapshot_with_rear_blend(ring_count, segment_count, camera_angle,
		start_distance, panel_count, camera_distance, blend_percent, true, true)
}

pub fn (simulation &Simulation) render_course_wire_without_markers(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int,
	camera_distance f32, blend_percent int) []CourseVertex {
	return simulation.render_course_snapshot_with_rear_blend(ring_count, segment_count, camera_angle,
		start_distance, panel_count, camera_distance, blend_percent, true, false)
}

fn (simulation &Simulation) render_course_snapshot_with_rear_blend(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int,
	camera_distance f32, blend_percent int, uniform_rings bool, include_markers bool) []CourseVertex {
	if ring_count < 2 || segment_count < 3 {
		return []CourseVertex{}
	}
	mut points := [][]CourseVertex{len: ring_count, init: []CourseVertex{len: segment_count}}
	mut distance := start_distance
	mut distance_step := f32(1)
	mut frames := []CourseRenderFrame{len: ring_count}
	mut path_frame := simulation.course_frame_at(distance)
	segment_points := course_segment_points(segment_count, camera_angle)
	line_brightness, light_brightness := tunnel_slice_brightness(ring_count, simulation.tunnel_dark_line_ratio())
	phase := course_render_phase(simulation.ship.course_position)
	blend_end := rear_track_blend_end(camera_distance, start_distance, 1, panel_count, blend_percent)
	dense_ring_count := if uniform_rings {
		ring_count
	} else if panel_count > 0 {
		int_min(ring_count - 1, panel_count + 2)
	} else {
		ring_count / 2
	}
	for ring in 0 .. ring_count {
		if ring > 0 {
			distance += distance_step
			path_frame = simulation.advance_course_frame(path_frame, distance)
		}
		depth := course_render_depth_base + distance * course_render_depth_scale
		frames[ring] = CourseRenderFrame{
			...path_frame
			light_brightness: sampled_course_brightness(light_brightness, f32(ring) - phase)
		}
		mut ring_brightness := sampled_course_brightness(line_brightness, f32(ring) - phase)
		if blend_percent > 0 {
			ring_brightness *= 1 - rear_track_blend_factor(distance, camera_distance, blend_end)
		}
		for segment in 0 .. segment_count {
			point := segment_points[segment]
			visible := course_side(point.angle, path_frame.slice) == 0
			x, y := course_surface_xy_from_unit(frames[ring], point)
			points[ring][segment] = CourseVertex{
				x:          x
				y:          y
				z:          depth
				brightness: if visible { ring_brightness } else { f32(0) }
			}
		}
		if ring >= dense_ring_count && distance_step < 80 {
			distance_step *= 1.15
		}
	}
	mut vertices := []CourseVertex{cap: (ring_count * segment_count + (ring_count - 1) * segment_count) * 2 + 768}
	for ring in 0 .. ring_count {
		for segment in 0 .. segment_count {
			append_course_vertex(mut vertices, points[ring][segment])
			append_course_vertex(mut vertices, points[ring][(segment + 1) % segment_count])
		}
	}
	for segment in 0 .. segment_count {
		for ring in 0 .. ring_count - 1 {
			append_course_vertex(mut vertices, points[ring][segment])
			append_course_vertex(mut vertices, points[ring + 1][segment])
		}
	}
	if include_markers {
		append_course_side_lights(mut vertices, frames, camera_angle)
	}
	simulation.append_visible_course_rings(mut vertices, frames, camera_angle)
	return vertices
}

pub fn (simulation &Simulation) render_course_backward_snapshot(ring_count int, segment_count int,
	camera_angle f32) []CourseVertex {
	return simulation.render_course_backward_snapshot_from(ring_count, segment_count, camera_angle, course_render_start_distance(simulation.ship.course_position))
}

pub fn (simulation &Simulation) render_course_backward_snapshot_from(ring_count int,
	segment_count int, camera_angle f32, start_distance f32) []CourseVertex {
	return simulation.render_course_backward_snapshot_from_with_panel_horizon(ring_count, segment_count, camera_angle, start_distance, 0)
}

pub fn (simulation &Simulation) render_course_backward_snapshot_from_with_panel_horizon(
	ring_count int, segment_count int, camera_angle f32, start_distance f32,
	panel_count int) []CourseVertex {
	return simulation.render_course_backward_snapshot_with_rear_blend(ring_count, segment_count, camera_angle, start_distance, panel_count, 0, 0, false, true)
}

pub fn (simulation &Simulation) render_course_backward_snapshot_from_with_rear_blend(
	ring_count int, segment_count int, camera_angle f32, start_distance f32,
	panel_count int, camera_distance f32, blend_percent int) []CourseVertex {
	return simulation.render_course_backward_snapshot_with_rear_blend(ring_count, segment_count, camera_angle, start_distance, panel_count, camera_distance, blend_percent, false, true)
}

pub fn (simulation &Simulation) render_course_backward_snapshot_from_with_draw_distance(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int,
	camera_distance f32, blend_percent int) []CourseVertex {
	return simulation.render_course_backward_snapshot_with_rear_blend(ring_count, segment_count,
		camera_angle, start_distance, panel_count, camera_distance, blend_percent, true, true)
}

pub fn (simulation &Simulation) render_course_backward_wire_without_markers(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int,
	camera_distance f32, blend_percent int) []CourseVertex {
	return simulation.render_course_backward_snapshot_with_rear_blend(ring_count, segment_count,
		camera_angle, start_distance, panel_count, camera_distance, blend_percent, true, false)
}

fn (simulation &Simulation) render_course_backward_snapshot_with_rear_blend(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, panel_count int,
	camera_distance f32, blend_percent int, uniform_rings bool, include_markers bool) []CourseVertex {
	if ring_count < 2 || segment_count < 3 {
		return []CourseVertex{}
	}
	mut points := [][]CourseVertex{len: ring_count, init: []CourseVertex{len: segment_count}}
	mut distance := start_distance
	mut distance_step := f32(-1)
	mut frames := []CourseRenderFrame{len: ring_count}
	mut path_frame := simulation.course_frame_at(distance)
	segment_points := course_segment_points(segment_count, camera_angle)
	line_brightness, light_brightness := tunnel_slice_brightness(ring_count, simulation.tunnel_dark_line_ratio())
	phase := course_render_phase(simulation.ship.course_position)
	blend_end := rear_track_blend_end(camera_distance, start_distance, -1, panel_count, blend_percent)
	dense_ring_count := if uniform_rings {
		ring_count
	} else if panel_count > 0 {
		int_min(ring_count - 1, panel_count + 2)
	} else {
		ring_count / 2
	}
	for ring in 0 .. ring_count {
		if ring > 0 {
			distance += distance_step
			path_frame = simulation.advance_course_frame(path_frame, distance)
		}
		depth := course_render_depth_base + distance * course_render_depth_scale
		frames[ring] = CourseRenderFrame{
			...path_frame
			light_brightness: sampled_course_brightness(light_brightness, f32(ring) + phase)
		}
		mut ring_brightness := sampled_course_brightness(line_brightness, f32(ring) + phase)
		if blend_percent > 0 {
			ring_brightness *= 1 - rear_track_blend_factor(distance, camera_distance, blend_end)
		}
		for segment in 0 .. segment_count {
			point := segment_points[segment]
			visible := course_side(point.angle, path_frame.slice) == 0
			x, y := course_surface_xy_from_unit(frames[ring], point)
			points[ring][segment] = CourseVertex{
				x:          x
				y:          y
				z:          depth
				brightness: if visible { ring_brightness } else { f32(0) }
			}
		}
		if ring >= dense_ring_count && distance_step > -80 {
			distance_step *= 1.15
		}
	}
	mut vertices := []CourseVertex{cap: (ring_count * segment_count + (ring_count - 1) * segment_count) * 2 + 768}
	for ring in 0 .. ring_count {
		for segment in 0 .. segment_count {
			append_course_vertex(mut vertices, points[ring][segment])
			append_course_vertex(mut vertices, points[ring][(segment + 1) % segment_count])
		}
	}
	for segment in 0 .. segment_count {
		for ring in 0 .. ring_count - 1 {
			append_course_vertex(mut vertices, points[ring][segment])
			append_course_vertex(mut vertices, points[ring + 1][segment])
		}
	}
	if include_markers {
		append_course_side_lights(mut vertices, frames, camera_angle)
	}
	simulation.append_visible_backward_course_rings(mut vertices, frames, camera_angle)
	return vertices
}

pub fn (simulation &Simulation) render_course_fill_snapshot(ring_count int, segment_count int,
	camera_angle f32) []CourseFillVertex {
	return simulation.render_course_fill_snapshot_from(ring_count, segment_count, camera_angle, course_render_start_distance(simulation.ship.course_position))
}

pub fn (simulation &Simulation) render_course_backward_fill_snapshot(ring_count int,
	segment_count int, camera_angle f32) []CourseFillVertex {
	return simulation.render_course_backward_fill_snapshot_from(ring_count, segment_count, camera_angle, course_render_start_distance(simulation.ship.course_position))
}

pub fn (simulation &Simulation) render_course_fill_snapshot_from(ring_count int,
	segment_count int, camera_angle f32, start_distance f32) []CourseFillVertex {
	panel_count := ring_count * course_panel_ring_numerator / course_panel_ring_denominator
	return simulation.render_course_fill_snapshot_in_direction(ring_count, segment_count, camera_angle, 1, start_distance, 0, 0, panel_count)
}

pub fn (simulation &Simulation) render_course_backward_fill_snapshot_from(ring_count int,
	segment_count int, camera_angle f32, start_distance f32) []CourseFillVertex {
	panel_count := ring_count * course_panel_ring_numerator / course_panel_ring_denominator
	return simulation.render_course_fill_snapshot_in_direction(ring_count, segment_count, camera_angle, -1, start_distance, 0, 0, panel_count)
}

pub fn (simulation &Simulation) render_course_fill_snapshot_from_with_rear_blend(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, camera_distance f32,
	blend_percent int, panel_count int) []CourseFillVertex {
	return simulation.render_course_fill_snapshot_in_direction(ring_count, segment_count, camera_angle, 1, start_distance, blend_percent, camera_distance, panel_count)
}

pub fn (simulation &Simulation) render_course_backward_fill_snapshot_from_with_rear_blend(ring_count int,
	segment_count int, camera_angle f32, start_distance f32, camera_distance f32,
	blend_percent int, panel_count int) []CourseFillVertex {
	return simulation.render_course_fill_snapshot_in_direction(ring_count, segment_count, camera_angle, -1, start_distance, blend_percent, camera_distance, panel_count)
}

fn rear_track_blend_end(camera_distance f32, start_distance f32, direction f32, panel_count int, percent int) f32 {
	panel_end := start_distance + direction * f32(panel_count)
	span := (panel_end - camera_distance) * direction
	return camera_distance + direction * f32_max(0, span) * f32_max(0, f32_min(100, f32(percent))) / 100
}

fn rear_track_blend_factor(distance f32, camera_distance f32, blend_end f32) f32 {
	span := blend_end - camera_distance
	if math.abs(f64(span)) <= 0.0001 {
		return 0
	}
	linear := f32_max(0, f32_min(1, (blend_end - distance) / span))
	// Keep the panel closed at the camera while its grid returns smoothly at
	// the slider's endpoint, including a reversed replay camera.
	return 1 - (1 - linear) * (1 - linear)
}

fn course_panel_opacity(brightness []f32, distance f32, start_distance f32,
	direction f32, phase f32, far_distance f32) f32 {
	row := (distance - start_distance) * direction - direction * phase
	remaining := clamp_f32((far_distance - distance) * direction, 0, 1)
	fade := remaining * remaining * (3 - 2 * remaining)
	return sampled_course_brightness(brightness, row) * fade
}

fn (simulation &Simulation) render_course_fill_snapshot_in_direction(ring_count int,
	segment_count int, camera_angle f32, direction f32, start_distance f32,
	blend_percent int, camera_distance f32, panel_count int) []CourseFillVertex {
	if ring_count < 3 || segment_count < 3 {
		return []CourseFillVertex{}
	}
	if panel_count <= 0 {
		return []CourseFillVertex{}
	}
	// Poly brightness keeps two terminal samples at zero to fade into the wire
	// mesh. Sample two extra rings so the setting denotes the actual number of
	// visible panel rows. Every terminal inset edge is interpolated between the
	// same two depth rings, keeping the solid/wire boundary on one depth plane.
	near_count := int_min(ring_count, int_max(3, panel_count + 2))
	mut frames := []CourseRenderFrame{len: near_count}
	mut path_frame := simulation.course_frame_at(start_distance)
	for ring in 0 .. near_count {
		distance := f32(ring) * direction + start_distance
		if ring > 0 {
			path_frame = simulation.advance_course_frame(path_frame, distance)
		}
		frames[ring] = CourseRenderFrame{
			...path_frame
		}
	}
	brightness := tunnel_poly_brightness(ring_count, near_count)
	phase := course_render_phase(simulation.ship.course_position)
	blend_end := rear_track_blend_end(camera_distance, start_distance, direction, panel_count, blend_percent)
	// Keep the far visibility plane at a fixed distance from the camera.
	// Sample two extra rings so a newly arriving panel starts with zero opacity
	// and gains visible area as it crosses this plane.
	far_distance := camera_distance + direction * (f32(panel_count) - course_render_rear_margin)
	poly_color := simulation.tunnel_poly_color()
	segment_points := course_segment_points(segment_count, camera_angle)
	mut vertices := []CourseFillVertex{cap: near_count * segment_count * 6}
	mut ring := near_count - 1
	for ring >= 1 {
		if sampled_course_brightness(brightness, f32(ring) - direction * phase) <= 0 {
			ring--
			continue
		}
		current := frames[ring]
		previous := frames[ring - 1]
		blend := if blend_percent > 0 {
			rear_track_blend_factor((current.distance + previous.distance) * 0.5, camera_distance, blend_end)
		} else {
			f32(0)
		}
		// Rear blending closes the panel gaps while retaining the panel color.
		// The matching wire snapshot fades its grid over the same interval, so
		// dark grid lines are replaced by a continuous surface at the camera.
		panel_color := poly_color
		far_edge_ratio := 0.9 + 0.1 * blend
		near_edge_ratio := 0.1 * (1 - blend)
		far_edge_distance := current.distance * far_edge_ratio + previous.distance * (1 - far_edge_ratio)
		near_edge_distance := current.distance * near_edge_ratio + previous.distance * (1 - near_edge_ratio)
		far_edge_alpha := course_panel_opacity(brightness, far_edge_distance, start_distance,
			direction, phase, far_distance)
		near_edge_alpha := course_panel_opacity(brightness, near_edge_distance, start_distance,
			direction, phase, far_distance)
		for segment in 0 .. segment_count {
			angle_a := segment_points[segment].angle
			angle_b := segment_points[segment + 1].angle
			for span in playable_course_angle_spans(angle_a, angle_b, current.slice) {
				start_point := if span.start == angle_a {
					segment_points[segment]
				} else {
					course_unit_point(span.start, camera_angle)
				}
				end_point := if span.end == angle_b {
					segment_points[segment + 1]
				} else {
					course_unit_point(span.end, camera_angle)
				}
				current_a := course_fill_point_from_unit(current, start_point, panel_color, far_edge_alpha)
				current_b := course_fill_point_from_unit(current, end_point, panel_color, far_edge_alpha)
				previous_a := course_fill_point_from_unit(previous, start_point, panel_color, near_edge_alpha)
				previous_b := course_fill_point_from_unit(previous, end_point, panel_color, near_edge_alpha)
				far_a := blend_course_fill_vertex(current_a, previous_b, far_edge_ratio, far_edge_alpha)
				far_b := blend_course_fill_vertex(current_b, previous_a, far_edge_ratio, far_edge_alpha)
				near_a := blend_course_fill_vertex(current_a, previous_b, near_edge_ratio, near_edge_alpha)
				near_b := blend_course_fill_vertex(current_b, previous_a, near_edge_ratio, near_edge_alpha)
				vertices << far_a
				vertices << far_b
				vertices << near_a
				vertices << far_a
				vertices << near_a
				vertices << near_b
			}
		}
		ring--
	}
	return vertices
}

fn course_fill_point_from_unit(frame CourseRenderFrame, point CourseUnitPoint, color RgbColor,
	alpha f32) CourseFillVertex {
	x, y := course_surface_xy_from_unit(frame, point)
	return CourseFillVertex{
		x: x
		y: y
		z: course_render_depth_base + frame.distance * course_render_depth_scale
		r: color.r
		g: color.g
		b: color.b
		a: alpha
	}
}

fn blend_course_fill_vertex(current CourseFillVertex, previous CourseFillVertex,
	ratio f32, alpha f32) CourseFillVertex {
	return CourseFillVertex{
		x: current.x * ratio + previous.x * (1 - ratio)
		y: current.y * ratio + previous.y * (1 - ratio)
		z: current.z * ratio + previous.z * (1 - ratio)
		r: current.r
		g: current.g
		b: current.b
		a: alpha
	}
}

fn append_course_side_lights(mut vertices []CourseVertex, frames []CourseRenderFrame,
	camera_angle f32) {
	panel_count := frames.len * course_panel_ring_numerator / course_panel_ring_denominator
	// Keep the boundary reference visible to the last complete sampled ring.
	// Configurable solid panels can now extend beyond the former 7/8 marker
	// horizon, so a fixed ratio could make the markers end before the panels.
	marker_count := int_max(1, frames.len - 1)
	marker_tail_length := int_max(1, marker_count - panel_count)
	append_course_side_lights_range(mut vertices, frames, camera_angle, 0, marker_count,
		panel_count, marker_tail_length)
}

fn append_course_side_lights_range(mut vertices []CourseVertex, frames []CourseRenderFrame,
	camera_angle f32, first_index int, marker_count int, panel_count int, marker_tail_length int) {
	for index in first_index .. marker_count {
		frame := frames[index]
		if frame.slice.full {
			continue
		}
		// The shared mesh fade becomes almost invisible before the solid panels
		// end. Give boundary markers their own relative tail so they remain useful
		// through the panel horizon and then fade across the wire-only preview.
		tail_ratio := if index < panel_count {
			f32(1)
		} else {
			f32(marker_count - index) / f32(marker_tail_length)
		}
		marker_brightness := if panel_count >= marker_count {
			frame.light_brightness
		} else {
			f32_max(frame.light_brightness, 0.18 * tail_ratio)
		}
		for angle in [frame.slice.left - f32(0.07), frame.slice.right + f32(0.07)] {
			radius := frame.radius / 1.05
			light_frame := CourseRenderFrame{ ...frame, radius: radius }
			center_x, center_y := course_surface_xy(light_frame, angle, camera_angle)
			depth := course_render_depth_base + frame.distance * course_render_depth_scale
			append_course_side_light(mut vertices, center_x, center_y, depth, course_side_light_brightness_base + marker_brightness)
		}
	}
}

// Draw yellow boundary markers through the requested border horizon without
// extending the panel or wire geometry. A full-circle slice has no side edges,
// so sparse square rings outline its entire walkable circumference instead.
pub fn (simulation &Simulation) render_course_side_lights_to_distance(camera_angle f32,
	start_distance f32, direction f32, first_ring int, last_ring int) []CourseVertex {
	if last_ring < first_ring || last_ring < 0 {
		return []CourseVertex{}
	}
	mut frames := []CourseRenderFrame{len: last_ring + 2}
	mut path_frame := simulation.course_frame_at(start_distance)
	_, light_brightness := tunnel_slice_brightness(frames.len, simulation.tunnel_dark_line_ratio())
	for ring in 0 .. frames.len {
		if ring > 0 {
			path_frame = simulation.advance_course_frame(path_frame,
				start_distance + direction * f32(ring))
		}
		remaining := f32(last_ring + 1 - ring) / f32(last_ring + 1)
		frames[ring] = CourseRenderFrame{
			...path_frame
			light_brightness: f32_max(light_brightness[ring], 0.06 + 0.12 * remaining)
		}
	}
	mut vertices := []CourseVertex{cap: (last_ring - first_ring + 1) * 16}
	append_course_side_lights_range(mut vertices, frames, camera_angle, first_ring,
		last_ring + 1, last_ring + 1, 1)
	for ring in first_ring .. last_ring + 1 {
		frame := frames[ring]
		if !frame.slice.full {
			continue
		}
		// Anchor the sparse rings to physical course slices. Otherwise they
		// would jump when the camera's recycled render rows advance.
		// The sampled rings sit on half-slices. A small bias keeps f32
		// rounding at that boundary from swapping a marker to a neighbor.
		world_slice := int(math.floor(f64(simulation.ship.course_position) + f64(frame.distance) + 0.51))
		if world_slice % 4 != 0 {
			continue
		}
		light_frame := CourseRenderFrame{ ...frame, radius: frame.radius / 1.05 }
		depth := course_render_depth_base + frame.distance * course_render_depth_scale
		for segment in 0 .. 8 {
			angle := f32(segment) * f32(math.pi) / 4
			x, y := course_surface_xy(light_frame, angle, camera_angle)
			append_course_side_light(mut vertices, x, y, depth,
				course_side_light_brightness_base + frame.light_brightness)
		}
	}
	return vertices
}

fn append_course_side_light(mut vertices []CourseVertex, center_x f32, center_y f32,
	depth f32, brightness f32) {
	half_size := f32(0.5) * 1.35 / 21
	points := [CourseVertex{
		x:          center_x - half_size
		y:          center_y - half_size
		z:          depth
		brightness: brightness
	}, CourseVertex{
		x:          center_x + half_size
		y:          center_y - half_size
		z:          depth
		brightness: brightness
	}, CourseVertex{
		x:          center_x + half_size
		y:          center_y + half_size
		z:          depth
		brightness: brightness
	}, CourseVertex{
		x:          center_x - half_size
		y:          center_y + half_size
		z:          depth
		brightness: brightness
	}]
	for index in 0 .. 4 {
		append_course_vertex(mut vertices, points[index])
		append_course_vertex(mut vertices, points[(index + 1) % 4])
	}
}

fn (simulation &Simulation) append_visible_course_rings(mut vertices []CourseVertex,
	frames []CourseRenderFrame, camera_angle f32) {
	if simulation.course.slices.len == 0 || simulation.course.rings.len == 0 || frames.len < 2 {
		return
	}
	start := simulation.ship.course_position
	max_distance := frames[frames.len - 1].distance
	for ring in simulation.course.rings {
		mut ring_distance := f32(ring.index) - start
		for ring_distance < 0 {
			ring_distance += f32(simulation.course.slices.len)
		}
		if ring_distance > max_distance {
			continue
		}
		mut frame_index := 1
		for frame_index < frames.len - 1 && frames[frame_index].distance < ring_distance {
			frame_index++
		}
		previous := frames[frame_index - 1]
		next := frames[frame_index]
		span := next.distance - previous.distance
		ratio := if span > 0 { (ring_distance - previous.distance) / span } else { f32(0) }
		center_x := previous.center_x * (1 - ratio) + next.center_x * ratio
		center_y := previous.center_y * (1 - ratio) + next.center_y * ratio
		radius := previous.radius * (1 - ratio) + next.radius * ratio
		depth := course_render_depth_base + ring_distance * course_render_depth_scale
		brightness := (previous.light_brightness * (1 - ratio) + next.light_brightness * ratio) * 0.7
		rotation := f32(simulation.tick) * f32(math.pi / 180)
		if ring.is_final {
			append_course_ring_geometry(mut vertices, center_x, center_y, depth, radius, 1.2, 1.5, 14, rotation - camera_angle, course_final_ring_brightness_base + brightness)
			append_course_ring_geometry(mut vertices, center_x, center_y, depth, radius, 1.6, 1.9, 14, -rotation - camera_angle, course_final_ring_brightness_base + brightness)
		} else {
			append_course_ring_geometry(mut vertices, center_x, center_y, depth, radius, 1.2, 1.4, 16, rotation - camera_angle, course_normal_ring_brightness_base + brightness)
		}
	}
}

fn (simulation &Simulation) append_visible_backward_course_rings(mut vertices []CourseVertex,
	frames []CourseRenderFrame, camera_angle f32) {
	if simulation.course.slices.len == 0 || simulation.course.rings.len == 0 || frames.len < 2 {
		return
	}
	start := simulation.ship.course_position
	minimum_distance := frames[frames.len - 1].distance
	for ring in simulation.course.rings {
		mut ring_distance := f32(ring.index) - start
		for ring_distance > 0 {
			ring_distance -= f32(simulation.course.slices.len)
		}
		if ring_distance < minimum_distance {
			continue
		}
		mut frame_index := 1
		for frame_index < frames.len - 1 && frames[frame_index].distance > ring_distance {
			frame_index++
		}
		previous := frames[frame_index - 1]
		next := frames[frame_index]
		span := next.distance - previous.distance
		ratio := if span < 0 { (ring_distance - previous.distance) / span } else { f32(0) }
		center_x := previous.center_x * (1 - ratio) + next.center_x * ratio
		center_y := previous.center_y * (1 - ratio) + next.center_y * ratio
		radius := previous.radius * (1 - ratio) + next.radius * ratio
		depth := course_render_depth_base + ring_distance * course_render_depth_scale
		brightness := (previous.light_brightness * (1 - ratio) + next.light_brightness * ratio) * 0.7
		rotation := f32(simulation.tick) * f32(math.pi / 180)
		if ring.is_final {
			append_course_ring_geometry(mut vertices, center_x, center_y, depth, radius, 1.2, 1.5, 14, rotation - camera_angle, course_final_ring_brightness_base + brightness)
			append_course_ring_geometry(mut vertices, center_x, center_y, depth, radius, 1.6, 1.9, 14, -rotation - camera_angle, course_final_ring_brightness_base + brightness)
		} else {
			append_course_ring_geometry(mut vertices, center_x, center_y, depth, radius, 1.2, 1.4, 16, rotation - camera_angle, course_normal_ring_brightness_base + brightness)
		}
	}
}

fn append_course_ring_geometry(mut vertices []CourseVertex, center_x f32, center_y f32,
	depth f32, tunnel_radius f32, inner_ratio f32, outer_ratio f32, segment_count int,
	rotation f32, brightness f32) {
	mut angle := f32(0)
	for _ in 0 .. segment_count {
		p1 := course_ring_point(center_x, center_y, depth, tunnel_radius, inner_ratio, angle + rotation)
		p2 := course_ring_point(center_x, center_y, depth, tunnel_radius, outer_ratio, angle + rotation)
		p3 := course_ring_point(center_x, center_y, depth, tunnel_radius, outer_ratio, angle + 0.2 + rotation)
		p4 := course_ring_point(center_x, center_y, depth, tunnel_radius, inner_ratio, angle + 0.2 + rotation)
		center := CourseVertex{
			x:          (p1.x + p2.x + p3.x + p4.x) / 4
			y:          (p1.y + p2.y + p3.y + p4.y) / 4
			z:          depth
			brightness: brightness
		}
		np1 := blend_course_ring_point(p1, center)
		np2 := blend_course_ring_point(p2, center)
		np3 := blend_course_ring_point(p3, center)
		np4 := blend_course_ring_point(p4, center)
		append_course_vertex(mut vertices, np1)
		append_course_vertex(mut vertices, np2)
		append_course_vertex(mut vertices, np2)
		append_course_vertex(mut vertices, np3)
		append_course_vertex(mut vertices, np3)
		append_course_vertex(mut vertices, np4)
		append_course_vertex(mut vertices, np4)
		append_course_vertex(mut vertices, np1)
		angle += 0.2
	}
}

fn course_ring_point(center_x f32, center_y f32, depth f32, tunnel_radius f32,
	radius_ratio f32, angle f32) CourseVertex {
	radius := tunnel_radius * radius_ratio / 1.05
	return CourseVertex{
		x: center_x + f32(math.cos(angle)) * radius
		y: center_y + f32(math.sin(angle)) * radius
		z: depth
	}
}

fn blend_course_ring_point(point CourseVertex, center CourseVertex) CourseVertex {
	return CourseVertex{
		x:          point.x * 0.7 + center.x * 0.3
		y:          point.y * 0.7 + center.y * 0.3
		z:          point.z
		brightness: center.brightness
	}
}

fn append_course_vertex(mut vertices []CourseVertex, point CourseVertex) {
	vertices << point
}

pub fn course_snapshot_checksum(vertices []CourseVertex) u64 {
	mut value := u64(14695981039346656037)
	value = fnv1a(value, u64(vertices.len))
	for vertex in vertices {
		value = fnv1a(value, u64(f32_bits(vertex.x)))
		value = fnv1a(value, u64(f32_bits(vertex.y)))
		value = fnv1a(value, u64(f32_bits(vertex.z)))
		value = fnv1a(value, u64(f32_bits(vertex.brightness)))
	}
	return value
}

pub fn course_fill_snapshot_checksum(vertices []CourseFillVertex) u64 {
	mut value := u64(14695981039346656037)
	value = fnv1a(value, u64(vertices.len))
	for vertex in vertices {
		value = fnv1a(value, u64(f32_bits(vertex.x)))
		value = fnv1a(value, u64(f32_bits(vertex.y)))
		value = fnv1a(value, u64(f32_bits(vertex.z)))
		value = fnv1a(value, u64(f32_bits(vertex.r)))
		value = fnv1a(value, u64(f32_bits(vertex.g)))
		value = fnv1a(value, u64(f32_bits(vertex.b)))
		value = fnv1a(value, u64(f32_bits(vertex.a)))
	}
	return value
}
