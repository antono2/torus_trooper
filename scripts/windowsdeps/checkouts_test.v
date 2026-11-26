module windowsdeps

import os
import rand

fn test_checkout_preserves_edits_and_recovers_failed_clone() {
	root := os.join_path(os.temp_dir(), 'torus source cache ' + rand.uuid_v4())
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	origin := os.join_path(root, 'origin')
	destination := os.join_path(root, 'cache with spaces')
	git(['init', origin]) or { panic(err) }
	file := os.join_path(origin, 'sample')
	os.write_file(file, 'original') or { panic(err) }
	git(['-C', origin, 'add', '.']) or { panic(err) }
	git(['-C', origin, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit',
		'-m', 'fixture']) or { panic(err) }
	revision := git(['-C', origin, 'rev-parse', 'HEAD']) or { panic(err) }
	mut refused := false
	checkout(os.join_path(root, 'missing'), revision, destination) or { refused = true }
	assert refused
	assert os.ls(root) or { panic(err) } == ['origin']
	checkout(origin, revision, destination) or { panic(err) }
	checkout(origin, revision, destination) or { panic(err) }
	os.write_file(os.join_path(destination, 'sample'), 'personal changes') or { panic(err) }
	refused = false
	checkout(origin, revision, destination) or { refused = err.msg().contains('Preserve local changes') }
	assert refused
	assert os.read_file(os.join_path(destination, 'sample')) or { panic(err) } == 'personal changes'
	refused = false
	checkout(origin, '0000000000000000000000000000000000000000', destination) or { refused = true }
	assert refused
	assert git(['-C', destination, 'rev-parse', 'HEAD']) or { panic(err) } == revision
}
