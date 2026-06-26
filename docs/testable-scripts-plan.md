# Plan: Testable CLIs — consolidated `test/`, runner, toward a `dot` toolchain

Status: Steps 1 and 3 are **done** on `feature/testable-scripts-lib`. Step 2
is **deferred** (no consumer yet). Step 4 (CI) and the `dot` north star remain
future work.

## North star — a single `dot` toolchain

The end state these scripts are converging on: every CLI we own follows one
shape — a thin shell wrapper over a tested Ruby helper — and sits under a
single toolchain fronted by a top-level `dot` command.

- **`dot` as a directory tool.** `dot` (or `dot ls`) lists the CLIs we have,
  each with a one-line description — a discoverable index instead of lore.
- **Cross-repo registry, not an auto-scan.** Some tools live in this repo
  (`gwt`, `proj`, `ruby-lsp-reap`, `md_to_commit`); others live in their own
  repos (e.g. `dox`). So the directory is a declarative manifest — name →
  location + description — that links tools wherever they live, rather than
  globbing one repo's `bin/`.
- **Consistent, tested base first.** `dot` is only cheap to build once the CLIs
  are uniform and listable. The test consolidation below is the groundwork:
  group everything the same way, prove it green with one command, then the
  directory is "enumerate the manifest, read each entry's description".

This section is the *why* behind the steps; the steps don't build `dot` yet.

## Goal (this branch)

Make it low-friction to write *tested* Ruby CLIs, keep the symlinked
`.claude/` surface clean, and expose one command that runs the whole suite
green.

## Background / why

- Tests lived in `.claude/scripts/`, which `setup.sh` symlinks into
  `~/.claude/` and which is tracked in this **public** repo — so every
  `*_test.rb`, `fixtures/`, and `test_helper.rb` shipped into the live Claude
  config dir.
- Subjects under test are split across `bin/` (`gwt-helper`, `proj-helper`,
  `ruby-lsp-reap`) and `.claude/scripts/` (`md_to_commit.rb`), so co-located
  tests couldn't be grouped consistently — the subjects are scattered across
  two homes.

## Non-goals

- Not retrofitting existing pure-logic scripts onto any runner abstraction —
  their style is already correct.
- No rubocop / linting setup — tests only.
- Not building `dot` itself on this branch — north star, not scope.

## Step 1 — Consolidate tests into a root `test/` (DONE)

Tests, fixtures, and `test_helper` moved out of `.claude/scripts/` into a root
`test/` whose shape mirrors where each subject lives:

```
test/
  test_helper.rb
  fixtures/                 # shared
  bin/                      # tests for bin/ executables
    gwt_helper_test.rb
    proj_helper_test.rb
    ruby_lsp_reap_test.rb
  scripts/                  # tests for .claude/scripts/ ruby scripts
    md_to_commit_test.rb
```

`load_script` paths re-anchored to the helper's new home (`../bin/...`,
`../.claude/scripts/...`); the md_to_commit fixture glob walks up to the shared
`test/fixtures`. `.claude/scripts/` now holds only real scripts. All 156 runs
stay green from the new location.

**Commit:** `refactor: Consolidate script tests into a root test/ dir`

## Step 2 — Shared side-effect runner lib (DEFERRED)

A `lib/SystemRunner` + `FakeRunner` for testing orchestration-shaped scripts
that are all side-effects with no pure core. **Deferred deliberately:** we have
no such script yet, so this would ship an unused library — scaffolding that
cuts against the goal of a clean, consolidated surface. Revisit when a real
side-effect-heavy CLI lands; the pure-logic-extraction style covers everything
we have today.

## Step 3 — One-command test runner (DONE)

A lean `Rakefile` with a `test` task globbing `test/**/*_test.rb`, set as the
default. `rake` runs all 156 examples in one process and exits non-zero on
failure, doubling as the local check and the future CI entry point.

**Commit:** `chore: Add a rake task to run the consolidated test suite`

## Step 4 — CI (future)

- `.github/workflows/test.yml`: trigger on push + PR, `ruby/setup-ruby`, run
  `rake`.
- **Gotcha:** green locally only because Ruby 4.0 bundles minitest and rake;
  `setup-ruby` won't have them without a `Gemfile`. Add a minimal `Gemfile`
  (`minitest`, `rake`) so `bundler-cache: true` works.

**Commit:** `ci: Run the Ruby test suite on push`

## Logistics

- Branch: `feature/testable-scripts-lib` (developed in a `gwt` worktree).
- Atomic commits, each leaving the suite green.
- Label `feature` on the PR.
- The deferred Step 2 follows a runner-injection + recording-fake pattern: the
  real runner shells out, a fake records commands without executing, so a
  side-effect-only script becomes assertable.
