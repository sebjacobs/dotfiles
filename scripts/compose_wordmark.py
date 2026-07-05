# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Regenerate this repo's wordmark (assets/logo-wordmark.png).

Thin wrapper over the portable `project-logo` skill, invoked with the dotfiles
mark and text. The composition logic and bundled DM Sans font live in
.claude/skills/project-logo/ so any project can reuse them.
"""
import runpy
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILL_SCRIPT = REPO / ".claude" / "skills" / "project-logo" / "compose_wordmark.py"

sys.argv = [
    str(SKILL_SCRIPT),
    "--mark", str(REPO / "assets" / "logo.png"),
    "--text", "dotfiles",
    "--output", str(REPO / "assets" / "logo-wordmark.png"),
]
runpy.run_path(str(SKILL_SCRIPT), run_name="__main__")
