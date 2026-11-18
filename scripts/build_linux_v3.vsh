// Build the pinned Linux toolchain and game inside a reusable per-manifest cache.
import compatpins
import crypto.sha256
import os
import rand

const project_name = 'torus_trooper'
const repositories = {
	'vulkan':     'https://github.com/antono2/vulkan.git'
	'opencl':     'https://github.com/antono2/opencl.git'
	'vkmemalloc': 'https://github.com/antono2/vulkan_memory_allocator.git'
	'memory':     'https://github.com/antono2/memory.git'
}

fn capture(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args[0]} exited with status ${result.exit_code}\n${result.output}')
	}
	return result.output.trim_space()
}

fn run(args []string) ! {
	executable_path := os.find_abs_path_of_executable(args[0]) or {
		return error('Missing build tool: ${args[0]}')
	}
	mut process := os.new_process(executable_path)
	process.set_args(args[1..])
	process.wait()
	defer { process.close() }
	if process.code != 0 {
		return error('${args[0]} exited with status ${process.code}')
	}
}

fn clone_pinned(url string, revision string, destination string) ! {
	if os.exists(os.join_path(destination, '.git')) {
		current := capture(['git', '-C', destination, 'rev-parse', 'HEAD'])!
		expected := capture(['git', '-C', destination, 'rev-parse', '--verify',
			'${revision}^{commit}'])!
		if current != expected {
			return error('Existing checkout at ${destination} is not at the tested revision ${revision}.')
		}
		return
	}
	if os.exists(destination) || os.is_link(destination) {
		return error('Cannot create checkout: ${destination} already exists.')
	}
	run(['git', 'clone', '--filter=blob:none', '--no-checkout', url, destination])!
	run(['git', '-C', destination, 'fetch', '--depth', '1', 'origin', revision])!
	run(['git', '-C', destination, 'checkout', '--detach', revision])!
}

fn verify_volk() ! {
	if os.is_file('/usr/include/volk.h') {
		return
	}
	probe := os.join_path(os.temp_dir(), 'torus-volk-' + rand.uuid_v4() + '.c')
	defer { os.rm(probe) or {} }
	os.write_file(probe, '#include <volk.h>\n')!
	if os.exec(['gcc', '-E', '-x', 'c', probe]).exit_code != 0 {
		return error('Missing volk.h. Install libvulkan-volk-dev or an equivalent Volk development package.')
	}
}

fn build(root string) ! {
	for tool in ['git', 'make', 'gcc'] {
		os.find_abs_path_of_executable(tool) or { return error('Missing build tool: ${tool}') }
	}
	pins := compatpins.resolve(root, platform: 'linux')!
	hash := sha256.sum(os.read_bytes(os.join_path(root, 'compatibility.json'))!).hex()
	cache_home := os.getenv_opt('XDG_CACHE_HOME') or { os.join_path(os.home_dir(), '.cache') }
	toolchain := os.abs_path(os.getenv_opt('TT_V3_TOOLCHAIN_DIR') or {
		os.join_path(cache_home, 'torus-trooper-v3', hash[..12])
	})
	compiler_dir := os.join_path(toolchain, 'v')
	headers := os.join_path(toolchain, 'Vulkan-Headers')
	module_hash := capture(['git', 'hash-object', os.join_path(root, 'v.mod')])!
	modules := os.join_path(toolchain, 'modules-' + module_hash)
	verify_volk()!
	os.mkdir_all(toolchain)!
	clone_pinned('https://github.com/KhronosGroup/Vulkan-Headers.git', pins['headers'] or {
		return error('Missing Linux Vulkan-Headers pin')
	}, headers)!
	clone_pinned('https://github.com/vlang/v.git', pins['v'], compiler_dir)!
	clone_pinned('https://github.com/vlang/vc.git', pins['vc'], os.join_path(compiler_dir, 'vc'))!
	clone_pinned('https://github.com/vlang/tccbin.git', pins['tcc'] or {
		return error('Missing Linux TCC pin')
	}, os.join_path(compiler_dir, 'thirdparty', 'tcc'))!
	compiler := os.join_path(compiler_dir, 'v')
	if !os.is_executable(compiler) {
		run(['make', '-C', compiler_dir, 'local=1'])!
	}
	for name, url in repositories {
		tag := pins['module_' + name] or { return error('Missing module pin: ${name}') }
		destination := os.join_path(modules, 'antono2', name)
		clone_pinned(url, tag, destination)!
	}
	compatpins.verify_modules(pins, modules)!
	os.setenv('VMODULES', modules, true)
	os.setenv('VULKAN_SDK', headers, true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.chdir(root)!
	run([compiler, 'run', 'scripts/check_installed_deps.vsh'])!
	run([compiler, '-cc', 'gcc', '-o', project_name, '.'])!
	println('Built ${os.join_path(root, project_name)} with pinned V3 and Vulkan headers.')
	println('Run silently with: ./torus_trooper --no-sound --volume 0')
}

fn main() {
	if os.args[1..] in [['--help'], ['-h']] {
		println('Usage: v run scripts/build_linux_v3.vsh')
		return
	}
	if os.args.len != 1 {
		eprintln('Usage: v run scripts/build_linux_v3.vsh')
		exit(2)
	}
	build(os.dir(@DIR)) or {
		eprintln(err)
		exit(1)
	}
}
