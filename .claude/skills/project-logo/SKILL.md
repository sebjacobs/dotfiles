---
name: project-logo
description: Generate a project logo — compose a square mark image next to a wordmark set in DM Sans onto a single PNG. Self-contained (font bundled) so it works from any project. Use when the user says "/project-logo", "generate a logo", "make a wordmark", "compose a logo", or wants to place a project name beside an icon.
---

# Project logo

Composes a square **mark** (icon) and a **wordmark** (the project name in DM Sans)
into one PNG on a parchment background. The font ships inside this skill, so it
runs unchanged in any project's checkout — nothing external to install beyond
`uv` handling the inline `pillow` dependency.

---

## Inputs to gather

Before running, confirm with the user:

- **Mark** — path to a square icon image (`--mark`). Required.
- **Text** — the wordmark, usually the project name (`--text`). Required.
- **Output** — where to write the PNG (`--output`). Suggest `assets/logo-wordmark.png`.

Optional overrides (mention only if the defaults look wrong): `--font-size`
(default 360), `--gap`, `--right-pad`, `--bg`/`--ink` as `R,G,B`, or a different
`--font`.

## Run

From the skill directory (`uv` reads the inline `pillow` dependency):

```bash
uv run "$CLAUDE_PROJECT_DIR/.claude/skills/project-logo/compose_wordmark.py" \
  --mark assets/logo.png \
  --text "my-project" \
  --output assets/logo-wordmark.png
```

If `$CLAUDE_PROJECT_DIR` isn't set, use the absolute path to this SKILL's
directory. Paths passed to `--mark`/`--output` are relative to the current
working directory, not the skill.

## Confirm

Read the saved PNG back so the user can see the result, and report its
dimensions from the script's `Saved …` line.

---

## Defaults

- Background `245,241,232` (parchment), ink `42,38,35`.
- Font: bundled `assets/DMSans-Regular.ttf`.
- Canvas height matches the mark; width = mark + gap + text + right pad.
