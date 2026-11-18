// Run bounded smoke-test commands with their own working directory and environment.
module testrun

import os
import rand
import strings
import time

const process_poll_interval = 10 * time.millisecond

pub struct Result {
pub:
	stdout string
	stderr string
}

pub fn temporary_directory(prefix string) !string {
	path := os.join_path(os.temp_dir(), prefix + rand.uuid_v4())
	os.mkdir(path, mode: 0o700)!
	return path
}

pub fn capture(binary string, args []string, root string, environment map[string]string, timeout time.Duration) !Result {
	if !os.is_file(binary) || !os.is_executable(binary) {
		return error('Expected an executable at ${binary}')
	}
	mut child := os.new_process(binary)
	child.set_args(args)
	child.set_work_folder(root)
	child.set_environment(environment)
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut stdout := strings.new_builder(256)
	mut stderr := strings.new_builder(256)
	timer := time.new_stopwatch()
	for {
		live := child.is_alive()
		out := child.stdout_read()
		err := child.stderr_read()
		stdout.write_string(out)
		stderr.write_string(err)
		if !live && out == '' && err == '' {
			child.wait()
			break
		}
		if timer.elapsed() >= timeout {
			if live {
				child.signal_kill()
				// V 0.5.2 marks the child aborted before wait() has reaped it.
				child.status = .running
				child.wait()
			}
			return error('${binary} timed out after ${timeout}\n${stdout.str()}${stderr.str()}')
		}
		if out == '' && err == '' {
			time.sleep(process_poll_interval)
		}
	}
	result := Result{
		stdout: stdout.str()
		stderr: stderr.str()
	}
	if child.code != 0 {
		return error('${binary} exited with status ${child.code}\n${result.stdout}${result.stderr}')
	}
	return result
}
