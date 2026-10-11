#!/usr/bin/env python3
"""Collect exact CI-tested desktop archives and prepare a reviewed draft release."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


REPOSITORY = 'antono2/torus_trooper'
REQUIRED_JOBS = {
    'Fresh Windows setup from ordinary PowerShell',
    'Windows V simulation and runtime tests', 'V simulation and runtime tests',
    'Package consumer (windows)', 'Package consumer (linux)',
    'ubuntu-latest C bridge', 'windows-latest C bridge', 'macos-latest C bridge',
}


def command(arguments):
    return subprocess.check_output(arguments, text=True).strip()


def validate_run(run, commit):
    if run['headSha'] != commit or run['headBranch'] != 'main':
        raise ValueError('Use successful main CI for the exact checked-out release commit')
    if run['status'] != 'completed' or run['conclusion'] != 'success':
        raise ValueError('Release CI must complete successfully')
    jobs = {job['name']: job for job in run['jobs']}
    if not REQUIRED_JOBS.issubset(jobs):
        raise ValueError('Release CI is missing required setup/runtime/package-consumer jobs')
    if any(job['conclusion'] != 'success' for job in run['jobs']):
        raise ValueError('Every release CI job must pass')


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_id', type=int, help='Successful main CI run with both package consumers')
    parser.add_argument('--output', type=Path, required=True, help='New directory for release assets')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    commit = command(['git', '-C', str(root), 'rev-parse', 'HEAD'])
    if command(['git', '-C', str(root), 'status', '--porcelain']):
        parser.error('Use a clean checkout of the release commit')
    version = re.search(r"version:\s*'([0-9]+\.[0-9]+\.[0-9]+)'", (root / 'v.mod').read_text())
    if not version:
        parser.error('v.mod must declare a release version')
    version = version[1]
    run = json.loads(command(['gh', 'run', 'view', str(args.run_id), '--repo', REPOSITORY,
                             '--json', 'headSha,headBranch,status,conclusion,jobs,url']))
    validate_run(run, commit)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    assets = {}
    for platform, extension in [('windows', 'zip'), ('linux', 'tar.gz')]:
        command(['gh', 'run', 'download', str(args.run_id), '--repo', REPOSITORY,
                 '--name', 'torus-trooper-' + platform + '-x86_64', '--dir', str(output)])
        filename = f'torus-trooper-{version}-{platform}-x86_64.{extension}'
        archive = output / filename
        if not archive.is_file():
            raise ValueError(f'CI archive name disagrees with v.mod: {filename}')
        assets[filename] = checksum(archive)
    (output / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in assets.items()))
    manifest = {'version': version, 'source_commit': commit, 'ci_run': run['url'],
                'compatibility': json.loads((root / 'compatibility.json').read_text()), 'sha256': assets}
    (output / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    changelog = (root / 'CHANGELOG.md').read_text()
    section = re.search(r'^## ' + re.escape(version) + r'\s*\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
    if not section:
        raise ValueError('Changelog must describe this release')
    (output / 'release-notes.txt').write_text(section[1].strip() + '\n\n'
        'Download the archive for your OS and keep its files together. A Vulkan-capable graphics driver is required.\n'
        'SHA256SUMS verifies the downloads; release-manifest.json records the source and passing CI run.\n')
    print(f'Prepared v{version} from {commit}: {output}')
    print('Review assets and notes, then follow docs/releasing.md. This command does not publish.')


if __name__ == '__main__':
    main()
