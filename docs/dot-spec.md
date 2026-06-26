# `dot` — the toolchain directory CLI (spec)

The north star from `docs/testable-scripts-plan.md`, now built: a single `dot`
command that lists the CLIs I own, each with a one-line description, so the
toolchain is discoverable instead of lore. `bin/dot` is Ruby in the `bin/svc`
shape — pure logic as module functions, side-effects behind a `System` seam,
tests in `test/bin/dot_test.rb`. Symlinked onto `$PATH` by `setup.sh` like every
other `bin/` script, so it runs from any repo. No zsh wrapper: `dot` needs no
shell-only behaviour.

## The registry: a declarative cross-repo manifest

Tools live in different repos — some here (`gwt`, `proj`, `svc`, `md_to_commit`),
some in their own (`dox`). So the directory is a hand-edited manifest, **not** a
`bin/` auto-scan: a tool joins `dot` by being listed, wherever its code lives.

`.config/dot/tools.yml` (symlinked to `~/.config/dot/tools.yml` by `setup.sh`):

```yaml
gwt:
  desc: Git worktree manager for .claude/worktrees
  location: bin/gwt-helper      # relative paths resolve against ~/dotfiles
  repo: dotfiles
dox:
  desc: docker-compose + git-worktree isolation helper
  location: ~/.local/bin/dox    # ~ and absolute paths used as-is
  repo: dox
```

- **`location`** — the tool's source file. A relative path resolves against
  `~/dotfiles` (the stable symlink `setup.sh` guarantees); a `~`- or `/`-prefixed
  path is used as-is, so out-of-repo tools link wherever they live.
- **`desc`** — the one-line directory entry.
- **`repo`** — which repo owns it, shown by `dot show` and a reminder that the
  manifest spans repos.

## Command surface

| Command | Purpose |
|---|---|
| `dot` / `dot ls` | List every registered tool, name + description, name-aligned |
| `dot show <tool>` | One tool's description, raw location, repo, and resolved path |
| `dot where <tool>` | Print the resolved absolute path — for `cd "$(dot where gwt)"` |
| `dot init` | Run `~/dotfiles/setup.sh` (absorbs the old `bin/dotfiles-init`) |

`show`/`where` resolve a query with the same exact → prefix → substring cascade
as `svc`/`gwt`/`proj` (`Dot.fuzzy_match`), so a unique abbreviation is enough and
an ambiguous one lists the candidates.

## `dot init` — replaces `bin/dotfiles-init`

`bin/dotfiles-init` was a one-line `sh ~/dotfiles/setup.sh`. Folding it into
`dot init` removes a standalone script whose only job was to find and run setup,
and puts the bootstrap behind the same directory command as everything else —
`dot init` reads as "initialise the dotfiles" next to `dot ls`.

## Technology & testing

Ruby + minitest, mirroring `bin/svc`:

- **Pure module functions** — `Dot.parse` (YAML string → sorted, normalised
  entries), `Dot.resolve_location` (relative vs `~`/absolute), `Dot.ls_lines`
  (name-aligned columns), `Dot.fuzzy_match`. The bug-prone bits, tested with zero
  side-effects.
- **`System` seam** — `read`/`exist?` for the manifest; a `run` lambda for
  `init`. Tests inject a fake so no file or `setup.sh` is touched.
- **Harness already exists** — `test/test_helper.rb`'s `load_script` + the
  `__FILE__ == $PROGRAM_NAME` guard. Run via `rake` on `ruby-4.0.5`.
