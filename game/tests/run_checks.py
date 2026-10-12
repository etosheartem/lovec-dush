#!/usr/bin/env python3
"""Run headless regressions, failing also on Godot errors that exit with code 0."""

import os
from pathlib import Path
import re
import subprocess
import sys


def main() -> int:
    project = Path(__file__).resolve().parents[1]
    markers = {"walkthrough": "WALKTHROUGH OK", "systems": "SYSTEMS OK",
               "audio_check": "AUDIO RUNTIME OK", "presentation": "PRESENTATION OK",
               "graphics": "GRAPHICS OK", "effects_check": "EFFECTS OK",
               "animation_check": "ANIMATION OK", "menu_effects_check": "MENU EFFECTS OK",
               "font_check": "FONT OK"}
    tests = sys.argv[1:] or list(markers)
    failed = False
    for test in tests:
        if test not in markers:
            print(f"Unknown test: {test}", file=sys.stderr)
            return 2
        command = [os.environ.get("GODOT_BIN", "godot"), "--headless", "--path", str(project),
                   "--script", f"res://tests/{test}.gd"]
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=90)
        except subprocess.TimeoutExpired as exc:
            print(f"FAIL {test}: timed out after 90 seconds", file=sys.stderr)
            for output in (exc.stdout, exc.stderr):
                if output:
                    print(output.decode(errors="replace") if isinstance(output, bytes) else output)
            failed = True
            continue
        output = result.stdout + result.stderr
        print(output, end="" if output.endswith("\n") else "\n")
        marker = markers[test]
        if result.returncode or marker not in output or re.search(r"^(?:SCRIPT )?ERROR:", output, re.M):
            print(f"FAIL {test}: exit={result.returncode}, success_marker={marker in output}", file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
