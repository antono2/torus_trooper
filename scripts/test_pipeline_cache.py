#!/usr/bin/env python3
"""Exercise cache roundtrip, corrupt payloads, stale devices and failed writes."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def checksum(data):
    value = 14695981039346656037
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    with tempfile.TemporaryDirectory() as temporary:
        temporary = Path(temporary)
        cache = temporary / 'pipeline.cache'
        def probe(path, loaded, default_root=None):
            environment = dict(os.environ, TT_GPU_PROFILE='1', TT_PIPELINE_CACHE_FILE=str(path))
            if default_root is not None:
                environment.pop('TT_PIPELINE_CACHE_FILE', None)
                key = 'LocalAppData' if os.name == 'nt' else 'XDG_CACHE_HOME'
                for existing in list(environment):
                    if existing.upper() == key.upper():
                        environment.pop(existing)
                environment[key] = str(default_root)
            result = subprocess.run(
                [str(binary), '--probe', '--no-sound', '--volume', '0', '--res', '800', '600',
                 '--data-file', str(temporary / 'player.json')], cwd=ROOT,
                env=environment,
                text=True, capture_output=True, check=True, timeout=60)
            output = result.stdout + result.stderr
            assert not re.search(r'Validation Error|VUID-', output, re.IGNORECASE), output
            assert f'cache_loaded={int(loaded)}' in output, output
            assert 'pipelines=8' in output, output
        probe(cache, False)
        saved = cache.read_bytes()
        assert saved[:8] == b'TTPCACHE' and len(saved) >= 48
        assert int.from_bytes(saved[8:16], 'little') == checksum(saved[16:])
        probe(cache, True)
        cache.write_bytes(b'truncated cache')
        probe(cache, False)
        corrupted = bytearray(saved)
        corrupted[-1] ^= 1
        cache.write_bytes(corrupted)
        probe(cache, False)
        for offset in [8, 16]:  # Native vendor ID and pipeline cache UUID.
            stale = bytearray(saved)
            stale[16 + offset] ^= 1
            stale[8:16] = checksum(stale[16:]).to_bytes(8, 'little')
            cache.write_bytes(stale)
            probe(cache, False)
        probe(cache, True)
        probe(temporary / 'missing-parent' / 'cache', False)
        assert not (temporary / 'missing-parent').exists()
        assert not list(temporary.glob('*.tmp'))
        default_root = temporary / 'default-cache-home'
        probe(cache, False, default_root=default_root)
        assert (default_root / 'torus_trooper' / 'pipelines.cache').is_file()
        probe(cache, True, default_root=default_root)
        blocked = temporary / 'not-a-directory'
        blocked.write_text('original')
        probe(cache, False, default_root=blocked)
        assert blocked.read_text() == 'original'
    print('Pipeline cache roundtrip, corrupt/stale fallback and failed-write startup passed.')


if __name__ == '__main__':
    main()
