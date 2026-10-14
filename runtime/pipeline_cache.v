// Chooses optional per-user pipeline storage without making cache I/O fatal.
module runtime

import os

fn renderer_pipeline_cache_path() string {
	if override := os.getenv_opt('TT_PIPELINE_CACHE_FILE') {
		// An empty override explicitly disables caching. The native reader
		// validates nonempty overrides; callers create their parent directory.
		return override
	}
	root := $if windows {
		configured := os.getenv('LocalAppData')
		if configured != '' { configured } else { os.join_path(os.home_dir(), 'AppData', 'Local') }
	} $else {
		configured := os.getenv('XDG_CACHE_HOME')
		if configured != '' { configured } else { os.join_path(os.home_dir(), '.cache') }
	}
	if !os.is_abs_path(root) {
		return ''
	}
	directory := os.join_path(root, 'torus_trooper')
	os.mkdir_all(directory) or { return '' }
	return os.join_path(directory, 'pipelines.cache')
}
