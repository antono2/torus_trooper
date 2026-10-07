// Polls the editable ship-model file and retains the last valid model after invalid edits.
module runtime

import json2
import os
import sim

const model_poll_interval_ms = i64(250)

struct LiveModelFile {
	path string
mut:
	last_content string
	last_poll_ms i64
	catalog      sim.ShipModelCatalog
	status       string
	revision     int
}

fn new_live_model_file(path string) LiveModelFile {
	return LiveModelFile{ path: path }
}

fn (mut file LiveModelFile) poll(now_ms i64) bool {
	if now_ms - file.last_poll_ms < model_poll_interval_ms {
		return false
	}
	file.last_poll_ms = now_ms
	return file.reload(false)
}

fn (mut file LiveModelFile) reload(force bool) bool {
	content := os.read_file(file.path) or {
		if file.last_content != '\x00' {
			file.last_content = '\x00'
			file.status = 'MODEL FILE MISSING'
			eprintln('could not read model file ${file.path}: ${err}')
		}
		return false
	}
	if !force && content == file.last_content {
		return false
	}
	file.last_content = content
	candidate := json2.decode[sim.ShipModelCatalog](content) or {
		file.status = 'MODEL PARSE FAILED'
		eprintln('could not parse model file ${file.path}: ${err}')
		return false
	}
	sim.validate_ship_model_catalog(candidate) or {
		file.status = 'MODEL INVALID'
		eprintln('invalid model file ${file.path}: ${err}')
		return false
	}
	file.catalog = candidate
	file.revision++
	file.status = 'MODELS LIVE ${file.revision}'
	println('TUNE models reloaded from ${file.path} (revision ${file.revision}).')
	return true
}
