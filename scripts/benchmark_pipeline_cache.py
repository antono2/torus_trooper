#!/usr/bin/env python3
"""Compare first-use executable copies with and without an application cache."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from benchmark_renderer import read_profile, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error('--runs must be positive')
    binary = args.binary.resolve()
    records = []
    with tempfile.TemporaryDirectory() as temporary:
        temporary = Path(temporary)
        cache = temporary / 'application.cache'
        def probe(name, use_cache):
            executable = temporary / (name + ('.exe' if os.name == 'nt' else ''))
            shutil.copy2(binary, executable)
            environment = dict(os.environ, TT_GPU_PROFILE='1')
            environment['TT_PIPELINE_CACHE_FILE'] = ''
            if use_cache:
                environment['TT_PIPELINE_CACHE_FILE'] = str(cache)
            result = subprocess.run(
                [str(executable), '--probe', '--no-sound', '--volume', '0', '--res', '800', '600',
                 '--data-file', str(temporary / (name + '.json'))],
                cwd=ROOT, env=environment, text=True, capture_output=True, check=True, timeout=60)
            return read_profile(result.stdout + result.stderr)
        records.append(dict(probe('seed', True), kind='seed'))
        if not cache.is_file():
            raise RuntimeError('Driver did not export a pipeline cache')
        for run in range(args.runs):
            # Alternate order to reduce systematic effects from warmup/load.
            order = [False, True] if run % 2 == 0 else [True, False]
            for use_cache in order:
                kind = 'cached' if use_cache else 'uncached'
                record = probe(f'{kind}-{run}', use_cache)
                assert record['cache_loaded'] == int(use_cache), record
                records.append(dict(record, kind=kind, run=run + 1))
        cache_bytes = cache.stat().st_size
    report = {'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'bridge_sha256': hashlib.sha256((ROOT / 'runtime/vulkan_bridge.h').read_bytes()).hexdigest(),
              'cache_bytes': cache_bytes, 'records': records}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Saved pipeline cache comparison to {args.output}')


if __name__ == '__main__':
    main()
