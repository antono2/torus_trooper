#!/usr/bin/env python3
"""Measure the game's real OpenCL kernels, packing, readback and CPU verification."""
import argparse
import hashlib
import json
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--v', default='v')
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error('--runs must be positive')
    environment = dict(os.environ, V_MACOS_V3_NO_FALLBACK='1', V_C_ERROR_BUG_REPORT_DISABLED='1')
    records = []
    with tempfile.TemporaryDirectory() as temporary:
        binary = Path(temporary) / ('benchmark.exe' if os.name == 'nt' else 'benchmark')
        with tempfile.NamedTemporaryFile(mode='w', suffix='_test.v', prefix='binding_benchmark_',
                                         dir=ROOT / 'sim', delete=False) as source:
            path = Path(source.name)
            source.write((ROOT / 'scripts/benchmarks/compute.v.template').read_text())
        try:
            subprocess.run([args.v, '-no-skip-unused', '-d', 'opencl_compute', '-d', 'opencl_dynamic',
                            '-cc', 'gcc', '-o', str(binary), str(path)],
                           cwd=ROOT, env=environment, check=True)
            for run in range(args.runs):
                result = subprocess.run([str(binary)], cwd=ROOT, env=environment,
                                        capture_output=True, text=True, check=True, timeout=120)
                batch = [json.loads(line.removeprefix('BENCH '))
                         for line in result.stdout.splitlines() if line.startswith('BENCH ')]
                if len(batch) != 6:
                    raise RuntimeError(result.stdout + result.stderr)
                records.extend(dict(record, run=run + 1) for record in batch)
                print(f'Completed fresh-process run {run + 1}/{args.runs}', flush=True)
        finally:
            path.unlink(missing_ok=True)
    report = {'compiler': subprocess.check_output([args.v, 'version'], text=True).strip(),
              'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'template_sha256': hashlib.sha256((ROOT / 'scripts/benchmarks/compute.v.template').read_bytes()).hexdigest(),
              'working_tree_changes': subprocess.check_output(['git', 'diff', '--stat'], cwd=ROOT, text=True).strip(),
              'records': records}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Saved {args.output}')


if __name__ == '__main__':
    main()
