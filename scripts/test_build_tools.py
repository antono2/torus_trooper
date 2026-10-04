#!/usr/bin/env python3
"""Regression checks for build diagnostics, shader failure handling and GPU IDs."""

from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from build_shaders import build_shaders
from check_compiler_diagnostics import ROOT, project_diagnostic


class CompilerDiagnosticsTests(unittest.TestCase):
    def test_project_paths_and_dependency_paths(self):
        for path in ("sim/simulation.v", "./runtime/menu.v", "torus_trooper.v",
                     str(ROOT / "runtime/vulkan_bridge.h")):
            self.assertTrue(project_diagnostic(f"{path}:12:4: warning: example"))
        self.assertTrue(project_diagnostic("\x1b[33mruntime/menu.v:12: notice: unused\x1b[0m"))
        self.assertTrue(project_diagnostic(r"C:\Game\runtime\menu.v:12:4: notice: unused", "C:/game"))
        self.assertTrue(project_diagnostic(r"C:\Game\runtime\bridge.h(12,4): warning C1234: example", "C:/game"))
        for path in ("toolchain/v/cmd/v/toolcache.v", "modules/antono2/vulkan/api.v",
                     "thirdparty/miniaudio/miniaudio.h", "../another-game/runtime/app.v"):
            self.assertFalse(project_diagnostic(f"{path}:12:4: warning: example"))
        self.assertFalse(project_diagnostic("simulation tick=12: warning: game message"))

    def test_command_status_and_diagnostics_are_preserved(self):
        wrapper = ROOT / "scripts/check_compiler_diagnostics.py"
        for script, expected in (
            ("print('compiled')", 0),
            ("print('runtime/menu.v:12:4: notice: unused')", 1),
            ("print('toolchain/v/cmd/v/toolcache.v:12:4: notice: unused')", 0),
            ("print('compile failed'); raise SystemExit(7)", 7),
        ):
            result = subprocess.run([sys.executable, str(wrapper), "--", sys.executable,
                                     "-c", script], capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            self.assertTrue(result.stdout.strip())


class ShaderBuildTests(unittest.TestCase):
    def test_bad_shader_does_not_replace_existing_binaries(self):
        with TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            output = Path(temporary) / "output"
            source.mkdir()
            output.mkdir()
            (source / "first.vert").write_text(
                "#version 450\nvoid main() { gl_Position = vec4(0); }\n")
            (source / "last.frag").write_text("#version 450\ninvalid shader\n")
            existing = output / "first.vert.spv"
            existing.write_bytes(b"previous shader binary")
            with self.assertRaises(subprocess.CalledProcessError):
                build_shaders(source, output)
            self.assertEqual(existing.read_bytes(), b"previous shader binary")
            self.assertEqual(list(output.iterdir()), [existing])

    def test_cpu_and_gpu_protocol_values_match(self):
        shader = (ROOT / "shaders/render_codes.glsl").read_text()
        gpu = dict(re.findall(r"const float (\w+) = ([\d.]+);", shader))
        for file, prefix in (("sim/render_codes.v", "render_"), ("sim/course.v", "course_")):
            cpu = dict(re.findall(r"const (\w+) = f32\(([\d.]+)\)", (ROOT / file).read_text()))
            names = [name for name in cpu if name.startswith(prefix) and
                     (file.endswith("render_codes.v") or name.endswith("_brightness_base"))]
            self.assertTrue(names, file)
            for name in names:
                self.assertIn(name, gpu)
                self.assertEqual(float(cpu[name]), float(gpu[name]), name)
        menu = (ROOT / "runtime/menu.v").read_text().split("enum TitleMenuItem {", 1)[1].split("}", 1)[0]
        ids = dict(re.findall(r"(\w+)\s*=\s*(\d+)", menu))
        header = dict(re.findall(r"#define TT_MENU_(\w+) (\d+)",
                                 (ROOT / "shaders/hud_state.h").read_text()))
        self.assertEqual({name.upper(): value for name, value in ids.items()}, header)
        self.assertEqual(len(ids), 8)


if __name__ == "__main__":
    unittest.main()
