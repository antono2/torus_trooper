#!/usr/bin/env python3
"""Measure renderer startup and opt-in GPU intervals on an isolated X11 display."""
import argparse
import ctypes
import ctypes.util
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


def close_window(window):
    """Send the same WM_DELETE_WINDOW request as the window manager's close button."""
    class MessageData(ctypes.Union):
        _fields_ = [('longs', ctypes.c_long * 5), ('bytes', ctypes.c_char * 20)]
    class ClientMessage(ctypes.Structure):
        _fields_ = [('type', ctypes.c_int), ('serial', ctypes.c_ulong),
                    ('send_event', ctypes.c_int), ('display', ctypes.c_void_p),
                    ('window', ctypes.c_ulong), ('message_type', ctypes.c_ulong),
                    ('format', ctypes.c_int), ('data', MessageData)]
    class Event(ctypes.Union):
        _fields_ = [('client', ClientMessage), ('padding', ctypes.c_long * 24)]
    library = ctypes.util.find_library('X11')
    if not library:
        raise RuntimeError('Renderer benchmark requires X11')
    x11 = ctypes.CDLL(library)
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x11.XInternAtom.restype = ctypes.c_ulong
    x11.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                              ctypes.c_long, ctypes.POINTER(Event)]
    x11.XSendEvent.restype = ctypes.c_int
    x11.XFlush.argtypes = [ctypes.c_void_p]
    x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
    display = x11.XOpenDisplay(None)
    if not display:
        raise RuntimeError('Cannot open benchmark display')
    try:
        event = Event()
        event.client.type = 33  # ClientMessage
        event.client.send_event = 1
        event.client.display = display
        event.client.window = int(window)
        event.client.message_type = x11.XInternAtom(display, b'WM_PROTOCOLS', 0)
        event.client.format = 32
        event.client.data.longs[0] = x11.XInternAtom(display, b'WM_DELETE_WINDOW', 0)
        if not x11.XSendEvent(display, int(window), 0, 0, ctypes.byref(event)):
            raise RuntimeError('Window close request failed')
        x11.XFlush(display)
    finally:
        x11.XCloseDisplay(display)


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
                # Hold the ordinary start action until the game acknowledges it.
                # A timed press can be missed between slow software-rendered frames.
                subprocess.run(['xdotool', 'keydown', 'Return'], env=environment, check=True)
                try:
                    deadline = time.monotonic() + 30
                    while 'Run started: NORMAL' not in log_path.read_text():
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError('Gameplay did not acknowledge start.\n' + log_path.read_text())
                        time.sleep(.1)
                finally:
                    subprocess.run(['xdotool', 'keyup', 'Return'], env=environment, check=True)
                time.sleep(args.seconds)
                close_window(window)
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
