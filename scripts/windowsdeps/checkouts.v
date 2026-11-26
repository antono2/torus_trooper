// Prepare pinned source dependencies without modifying existing checkouts.
module windowsdeps

import os
import rand
import scripts.testrun
import time
import v.vmod

const git_timeout = 5 * time.minute

fn git(args []string) !string {
	result := testrun.capture(os.find_abs_path_of_executable('git')!, args, os.getwd(),
		os.environ(), git_timeout)!
	return result.stdout.trim_space()
}

fn verify(directory string, revision string) ! {
	if !os.exists(os.join_path(directory, '.git')) {
		return error('Existing directory is not a managed Git checkout: ${directory}. Choose another cache directory.')
	}
	head := git(['-C', directory, 'rev-parse', 'HEAD'])!
	expected := git(['-C', directory, 'rev-parse', '--verify', '${revision}^{commit}'])!
	if head != expected {
		return error('Checkout is not at the tested revision ${revision}: ${directory}. Choose another cache directory.')
	}
	if git(['-C', directory, 'status', '--porcelain'])! != '' {
		return error('Preserve local changes in ${directory}, or choose another cache directory.')
	}
}

pub fn checkout(repository string, revision string, directory string) ! {
	if os.exists(directory) || os.is_link(directory) {
		verify(directory, revision)!
		return
	}
	os.mkdir_all(os.dir(directory))!
	stage := directory + '.setup-' + rand.uuid_v4()
	defer { os.rmdir_all(stage) or {} }
	git(['-c', 'core.longpaths=true', 'clone', '--filter=blob:none', '--no-checkout', '--', repository,
		stage])!
	git(['-C', stage, 'fetch', '--depth', '1', 'origin', revision])!
	git(['-C', stage, 'checkout', '--detach', revision])!
	verify(stage, revision)!
	os.rename_dir(stage, directory) or {
		if !os.is_dir(directory) {
			return err
		}
		verify(directory, revision)!
	}
}

fn dependencies(root string, modules string, mut checked map[string]string) ! {
	manifest := vmod.from_file(os.join_path(root, 'v.mod'))!
	for dependency in manifest.dependencies {
		name, tag := dependency.rsplit_once('@') or {
			return error('Dependency is not pinned in ${root}: ${dependency}')
		}
		module_name := name.all_after_last('.')
		if name != 'antono2.${module_name}' || module_name == '' || tag == ''
			|| !module_name.bytes().all(it.is_alnum() || it == `_`) {
			return error('Expected a pinned antono2 module: ${dependency}')
		}
		if previous := checked[name] {
			if previous != tag {
				return error('Conflicting dependency pins for ${name}: ${previous} and ${tag}')
			}
			continue
		}
		repository := if module_name == 'vkmemalloc' {
			'vulkan_memory_allocator'
		} else {
			module_name
		}
		directory := os.join_path(modules, 'antono2', module_name)
		checkout('https://github.com/antono2/${repository}.git', tag, directory)!
		checked[name] = tag
		dependencies(directory, modules, mut checked)!
	}
}

pub fn install_modules(root string, modules string) ! {
	mut checked := map[string]string{}
	dependencies(root, modules, mut checked)!
}
