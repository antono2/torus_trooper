#!/usr/bin/env python3
"""Measure renderer startup and opt-in GPU intervals on an isolated X11 display."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
PROFILE = re.compile(r'^GPU_PROFILE (.+)$', re.MULTILINE)


def read_profile(log):
    if re.search(r'Validation Error|VUID-', log, re.IGNORECASE):
        raise RuntimeError(log)
    match = PROFILE.search(log)
    if not match:
        raise RuntimeError('Renderer did not report profiling results.\n' + log)
    fields = dict(item.split('=', 1) for item in match[1].split())
    return {key: float(value) for key, value in fields.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--seconds', type=float, default=3)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.runs < 1 or args.seconds <= 0:
        parser.error('runs and seconds must be positive')
    binary = args.binary.resolve()
    environment = dict(os.environ, TT_GPU_PROFILE='1', TT_PIPELINE_CACHE_FILE='')
    records = []
    with tempfile.TemporaryDirectory() as temporary:
        temporary = Path(temporary)
        for run in range(args.runs):
            result = subprocess.run(
                [str(binary), '--probe', '--no-sound', '--volume', '0', '--res', '800', '600',
                 '--data-file', str(temporary / f'probe-{run}.json')],
                cwd=ROOT, env=environment, text=True, capture_output=True, check=True, timeout=60)
            records.append(dict(read_profile(result.stdout + result.stderr), kind='startup', run=run + 1))
        log_path = temporary / 'game.log'
        with log_path.open('w') as log:
            process = subprocess.Popen(
                [str(binary), '--no-sound', '--volume', '0', '--res', '800', '600',
                 '--data-file', str(temporary / 'game.json')], cwd=ROOT, env=environment,
                stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 60
                while 'Renderer bootstrap complete' not in log_path.read_text():
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError(log_path.read_text())
                    time.sleep(.1)
                window = subprocess.check_output(
                    ['xdotool', 'search', '--onlyvisible', '--pid', str(process.pid),
                     '--name', '^Torus Trooper'], env=environment, text=True).split()[0]
                subprocess.run(['xdotool', 'windowfocus', '--sync', window], env=environment, check=True)
                def press(key):
                    if process.poll() is not None:
                        return
                    subprocess.run(['xdotool', 'keydown', key], env=environment, check=True)
                    time.sleep(.3)
                    subprocess.run(['xdotool', 'keyup', key], env=environment, check=True)
                    time.sleep(.3)
                press('Return')  # Start Normal gameplay using its ordinary menu action.
                time.sleep(args.seconds)
                press('Escape')
                press('Up')  # Wrap the Normal selection to Exit.
                press('Return')
                if process.wait(timeout=20):
                    raise RuntimeError(log_path.read_text())
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
        log = log_path.read_text()
        if 'Run started: NORMAL' not in log:
            raise RuntimeError('Gameplay did not start.\n' + log)
        gameplay = read_profile(log)
        if gameplay['timestamp_bits'] and not gameplay['samples']:
            raise RuntimeError('Supported GPU queries produced no samples.\n' + log)
        records.append(dict(gameplay, kind='gameplay'))
    report = {'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'bridge_sha256': hashlib.sha256((ROOT / 'runtime/vulkan_bridge.h').read_bytes()).hexdigest(),
              'validation_layers': environment.get('VK_INSTANCE_LAYERS', ''),
              'records': records}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Saved renderer measurements to {args.output}')


if __name__ == '__main__':
    main()
