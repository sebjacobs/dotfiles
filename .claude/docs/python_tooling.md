# Python tooling conventions

## Use uv, not pip / python3

Always use `uv` for Python dependency management and running scripts:

- `uv add <package>` — add a dependency (creates `.venv` if needed)
- `uv run python <script>` — run a script in the project virtualenv
- `uv run pytest` — run tests
- `uv init --bare` — initialise a bare uv project (no `main.py`)

Never use `pip`, `pip3`, or call `python3` directly — use `uv run python` instead.

Never use `pip`, `pip3`, or call `python3` directly.

## Use uvx / uv tool, not pipx

For running one-off tools (the equivalent of `pipx run`), use `uvx` or `uv tool run`:

- `uvx <tool>` — run a tool without installing it
- `uv tool install <tool>` — install a tool globally (equivalent of `pipx install`)
- `uv tool run <tool>` — same as `uvx`

Never use `pipx` — use `uv tool` instead.

The `uv` binary is at `/opt/homebrew/bin/uv`.
