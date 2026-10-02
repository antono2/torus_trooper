module runtime

import os
import sim

fn test_tuning_model_template_loads_and_invalid_edit_keeps_last_good() {
	mut file := new_live_model_file(os.join_path(@VMODROOT, 'models', 'tune_models.json'))
	assert file.reload(true)
	assert file.revision == 1
	assert !file.catalog.enemy_small.enabled
	assert file.catalog.enemy_small.parts.len > 0

	directory := os.join_path(os.temp_dir(), 'torus_model_reload_${os.getpid()}')
	path := os.join_path(directory, 'models.json')
	defer { os.rmdir_all(directory) or {} }
	os.mkdir_all(directory) or { assert false, err.msg() }
	mut live := new_live_model_file(path)
	assert !live.reload(true)
	assert live.status == 'MODEL FILE MISSING'
	first := '{"version":1,"enemy_small":{"enabled":true,"parts":[{"kind":"round_hull","color":4,"sections":[{"z":-1,"half_width":0.2,"half_height":0.2},{"z":1,"half_width":0.01,"half_height":0.01}]}]}}'
	os.write_file(path, first) or { panic(err) }
	assert live.poll(1000)
	assert live.revision == 1
	assert live.catalog.enemy_small.enabled
	first_vertices := sim.render_ship_mesh_previews_with_models([sim.ShipMeshPreview{
		kind:  0
		scale: 1
	}], live.catalog)
	assert first_vertices.len > 0
	os.write_file(path, '{bad') or { panic(err) }
	assert !live.poll(1300)
	assert live.status == 'MODEL PARSE FAILED'
	assert live.revision == 1
	assert live.catalog.enemy_small.enabled
	assert !live.poll(1600)
	os.write_file(path, first.replace('"color":4', '"color":999')) or { panic(err) }
	assert !live.poll(1900)
	assert live.status == 'MODEL INVALID'
	assert live.revision == 1
	os.write_file(path, first.replace('"color":4', '"color":6')) or { panic(err) }
	assert live.poll(2200)
	assert live.revision == 2
	second_vertices := sim.render_ship_mesh_previews_with_models([sim.ShipMeshPreview{
		kind:  0
		scale: 1
	}], live.catalog)
	assert second_vertices.len == first_vertices.len
	assert second_vertices[0].r != first_vertices[0].r
}
