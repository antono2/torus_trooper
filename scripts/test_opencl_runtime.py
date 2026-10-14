#!/usr/bin/env python3
"""Verify optional OpenCL loading and deterministic fallback in a built game."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def run(binary, backend, environment):
    result = subprocess.run(
        [str(binary), '--headless', '--ticks', '600', '--compute', backend,
         '--no-sound', '--volume', '0'],
        env=environment, capture_output=True, text=True, timeout=60, check=True,
    )
    fields = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    assert fields['compute_requested'] == backend, result.stdout
    return fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--require-opencl', action='store_true')
    args = parser.parse_args()
    binary = args.binary.resolve()
    if sys.platform == 'linux':
        linked = subprocess.check_output(['ldd', str(binary)], text=True)
        assert 'libOpenCL' not in linked, linked

    environment = dict(os.environ)
    environment.pop('OPENCL_LIBRARY', None)
    cpu = run(binary, 'cpu', environment)
    available = run(binary, 'opencl', environment)
    if args.require_opencl:
        assert available['compute_active'] == 'opencl', available
        assert int(available['compute_verified_batches']) > 0, available

    with tempfile.TemporaryDirectory() as temporary:
        missing = run(binary, 'opencl', dict(
            environment, OPENCL_LIBRARY=str(Path(temporary) / 'missing-opencl-runtime'),
        ))
    assert missing['compute_active'] == 'cpu', missing
    assert 'OpenCL runtime unavailable' in missing['opencl_fallback'], missing
    assert int(missing['compute_fallback_batches']) > 0, missing
    assert missing['compute_verified_batches'] == '0', missing
    checksums = ['checksum', 'render_checksum', 'course_checksum',
                 'course_fill_checksum', 'course_backward_checksum',
                 'course_backward_fill_checksum', 'compute_checksum']
    for key in checksums:
        assert missing[key] == cpu[key], (key, cpu[key], missing[key])
        assert available[key] == cpu[key], (key, cpu[key], available[key])
    print('Dynamic OpenCL execution and missing-loader CPU fallback preserve all checksums.')


if __name__ == '__main__':
    main()
