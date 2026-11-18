// Resolve the tested toolchain and dependency pins shared by setup and CI.
module compatpins

import os
import x.json2

const immutable_fields = ['v', 'vc', 'tcc', 'linux_vc', 'linux_tcc', 'headers', 'volk', 'v3_v',
	'v3_vc']
const required_fields = ['v', 'vc', 'modules', 'glfw', 'ci_sdk', 'ci_runtime']

@[params]
pub struct Profile {
pub:
	platform string
	variant  string = 'docking'
	compiler string = 'stable'
}

fn name_is_safe(name string) bool {
	return name != '' && name.bytes().all((it >= `a` && it <= `z`) || it.is_digit() || it == `_`)
}

fn release_is_valid(version string) bool {
	parts := version.split('.')
	return parts.len == 3 && parts.all(it != '' && it.bytes().all(it.is_digit()))
}

fn pin_value(pins map[string]json2.Any, key string) string {
	value := pins[key] or { return '' }
	return if value is string { value } else { '' }
}

fn project_info(root string, modules map[string]json2.Any) !string {
	quoted := os.read_file(os.join_path(root, 'v.mod'))!.split("'")
	mut version := ''
	for index := 1; index < quoted.len; index += 2 {
		value := quoted[index]
		if quoted[index - 1].trim_space().ends_with('version:') {
			version = value
		}
		if value.starts_with('antono2.') && value.contains('@') {
			name, declared := value['antono2.'.len..].split_once('@') or { continue }
			if name_is_safe(name) && pin_value(modules, name) != declared {
				return error('v.mod and compatibility.json disagree for ${name}: ${declared}')
			}
		}
	}
	if !release_is_valid(version) {
		return error('v.mod must declare a release version')
	}
	return version
}

pub fn resolve(root string, options Profile) !map[string]string {
	host := if os.user_os() == 'windows' { 'windows' } else { 'linux' }
	platform := if options.platform == '' { host } else { options.platform }
	if platform !in ['windows', 'linux'] || options.variant !in ['docking', 'standard']
		|| options.compiler !in ['stable', 'v3'] {
		return error('invalid platform, variant, or compiler profile')
	}
	pins :=
		json2.decode[map[string]json2.Any](os.read_file(os.join_path(root, 'compatibility.json'))!)!
	if (pins['schema_version'] or { json2.Any(0) }).int() != 1 {
		return error('Unsupported compatibility schema_version')
	}
	for key in immutable_fields {
		if key in pins {
			commit := pin_value(pins, key)
			if commit.len != 40 || !commit.bytes().all(it.is_digit() || (it >= `a` && it <= `f`)) {
				return error('${key} must be an immutable Git commit')
			}
		}
	}
	for key in required_fields {
		if key != 'modules' && pin_value(pins, key) == '' {
			return error('Missing compatibility field: ${key}')
		}
	}
	modules_value := pins['modules'] or { return error('Missing compatibility field: modules') }
	if modules_value !is map[string]json2.Any {
		return error('Missing compatibility field: modules')
	}
	modules := modules_value.as_map()
	if modules.len == 0 {
		return error('Missing compatibility field: modules')
	}
	mut outputs := map[string]string{}
	for key, value in pins {
		if value is string {
			outputs[key] = value
		}
	}
	outputs['project_version'] = project_info(root, modules)!
	for name, value in modules {
		tag := value.str()
		version := tag.trim_string_right('-standard')
		if !name_is_safe(name) || !version.starts_with('v') || !release_is_valid(version[1..]) {
			return error('Invalid module pin: ${name}=${tag}')
		}
		outputs['module_' + name] = tag
	}
	if platform == 'linux' {
		for key in ['vc', 'tcc'] {
			if selected := outputs['linux_' + key] {
				outputs[key] = selected
			}
		}
	}
	if options.variant == 'standard' && 'module_imgui' in outputs {
		outputs['module_imgui'] = outputs['imgui_standard'] or {
			return error('standard profile requires imgui_standard')
		}
	}
	if options.compiler == 'v3' {
		for key in ['v', 'vc'] {
			outputs[key] = outputs['v3_' + key] or { return error('V3 profile requires v3_${key}') }
		}
	}
	for key, value in outputs {
		if !name_is_safe(key) || value.contains_any('\r\n') {
			return error('Unsafe compatibility output: ${key}')
		}
	}
	return outputs
}

fn revision(checkout string, ref string) !string {
	result := os.exec(['git', '-C', checkout, 'rev-parse', '--verify', ref])
	if result.exit_code != 0 {
		return error('could not resolve ${ref} in ${checkout}: ${result.output.trim_space()}')
	}
	return result.output.trim_space()
}

pub fn verify_modules(outputs map[string]string, modules string) ! {
	for key, tag in outputs {
		if !key.starts_with('module_') {
			continue
		}
		name := key['module_'.len..]
		checkout := os.join_path(modules, 'antono2', name)
		if revision(checkout, 'HEAD')! != revision(checkout, 'refs/tags/${tag}^{commit}')! {
			return error('Installed ${name} does not match ${tag}: ${checkout}')
		}
	}
}
