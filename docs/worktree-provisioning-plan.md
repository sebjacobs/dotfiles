# Worktree provisioning — `.env` project-name isolation + `.gwt` hooks plan

**Status:** engine fix landed; `.gwt` hook layer still to do. The collision bug
(a worktree inheriting the main checkout's `COMPOSE_PROJECT_NAME`) is closed in
the dox engine via the linked-worktree self-heal plus `setup --force` (step 1
below). The richer `.gwt` worktree-lifecycle hook layer it motivated (step 2/3,
spanning the `gwt` helper in `dotfiles`, `zsh/gwt.zsh`) is still outstanding.

## The bug

`dox` pins `COMPOSE_PROJECT_NAME` into a checkout's `.env` on `up`/`setup`
(commit `91a4b83`) so a bare `docker compose` resolves the same project the engine
does — necessary when the compose file lives in a subdirectory (e.g. `.local/`),
where compose would otherwise default the project to that subdir's basename.

But `.env` is always seeded into new worktrees (it carries `DOX_FILE` /
`COMPOSE_FILE`, so every worktree needs it). So a new worktree inherits the main
checkout's `COMPOSE_PROJECT_NAME=<repo>`, and `isolate_compose_project` **returns
early on any explicit value** — it neither recomputes nor re-pins. The worktree
then runs under the main checkout's project name: shared containers, network, and
DB volume. Worktree isolation is silently defeated.

This bites any worktree created after the pin landed, regardless of creator:
- `gwt`-born worktrees (seed `.env` via `.worktreeinclude`),
- Claude Code-born worktrees (background sessions, `Agent isolation: worktree` —
  these honour `.worktreeinclude` but **do not** run `gwt`/`.gwt` hooks),
- manually moved worktrees (the pre-existing "moving a worktree leaves the pin
  stale — delete it manually" caveat noted in `91a4b83`).

## The fix — layered, no single point of failure

### 1. dox engine (this repo) — the universal correctness layer

- **Linked-worktree self-heal in plain `up`/`setup`.** In a linked worktree,
  treat a `.env` `COMPOSE_PROJECT_NAME` that is a stale/inherited dox pin as not
  authoritative: recompute this checkout's own name, set it in-process (so the
  command is correct immediately), and re-pin the worktree's `.env`. Two ways to
  decide "stale", in increasing fidelity:
  - *heuristic*: the pin equals the parent repo's name (the value main would
    pin) → it's the inherited one → recompute;
  - *marker-path (preferred)*: extend the existing managed-pin marker comment to
    record the checkout path it was computed for; heal when that path ≠ the
    current root. This also distinguishes a dox-written pin (heal it) from a
    user's deliberate `COMPOSE_PROJECT_NAME` (respect it), and fixes moved
    worktrees for free.
  - Make `persist` idempotent: only rewrite/announce when the value actually
    changes.
- **`dox setup --force`.** The authoritative "provision this checkout" command:
  recompute and **overwrite** the `.env` pin (ignoring any existing value — what
  `--force` buys over plain `setup`) and ensure the shared/external volumes (it
  already does the latter). Reusable by hand, by the gwt hook, and as the
  explicit re-provision lever.
- **`dox install-hooks`** (idempotent). Writes a managed `.gwt` block (marker
  comment, like the `.env` pin management) registering dox's hooks, without
  clobbering hand-written ones. Folded into a root `dox setup` or run explicitly.

Steps 1 (heal) + (`setup --force`) close the bug for **every** worktree today,
hook or no hook — they don't depend on the `.gwt` work below.

### 2. `gwt` + `.gwt` (dotfiles) — the richer provisioning layer

A declarative `.gwt` file at the repo root, hooks keyed by gwt lifecycle event,
each with a default action and forwarded option flags (each flag may carry a
value). Motivated by the `stock-fetch` project's `db/bootstrap.py` (`--read`:
symlink prod DBs read-only; `--seed`: migrate + load seed data).

```yaml
# .gwt — worktree lifecycle
seed:
  include: .worktreeinclude          # files copied into a new worktree
  scrub:                             # checkout-specific keys stripped from seeded copies
    .env: [COMPOSE_PROJECT_NAME]     # alternative/eager .env fix, declaratively

hooks:
  post-add:   { run: [dox, setup, --force] }   # provision eagerly on create
  pre-rm:     { run: [dox, down] }              # stop the stack before the worktree dies
  # project example:
  # post-add: { run: [db/bootstrap.py], options: { mode: {values: [read, seed], default: read}, from: {} } }
```

- **`gwt add <branch> [--seed] [--from main]`** — create, apply `seed`, run
  `post-add` with chosen options.
- **`gwt init [<name>|--all] [--force]`** — re-provision an existing worktree
  (re-apply `seed` + re-run hooks; idempotent; `--force` overwrites). **Replaces
  `gwt cp`** — re-provisioning is a more meaningful unit than copying one path.
- **`pre-rm: dox down`** removes the leaked-stack / phantom-dir class of problem
  at the source (a worktree's stack is always torn down before the directory is
  removed).

dox self-registers `post-add: dox setup --force` via `install-hooks`, so a
dox+gwt project gets eager provisioning for free; the engine self-heal (step 1)
remains the backstop for worktrees gwt never sees (Claude Code-born, manual).

## Implementation order

1. **dox-cli — DONE:** `setup --force` + the linked-worktree heal (+ tests).
   Closes the collision bug universally. The heal landed as a *heuristic* (a .env
   `COMPOSE_PROJECT_NAME` equal to the parent repo's name is the inherited one →
   recompute), restricted to `.env`-sourced values so a deliberate shell export
   is always honoured. The marker-path refinement (records the checkout path in
   the pin comment, so it also fixes moved worktrees and distinguishes a user's
   own `.env` value) was deferred — fold it in with step 2 if/when it's needed.
2. **dox-cli next:** `dox install-hooks` writing the managed `.gwt` block.
3. **dotfiles:** the `.gwt` hook engine in `gwt.zsh` (`post-add` / `pre-rm` /
   `gwt init`) that makes the hook actually fire.

## Open questions

- ~~Heal fidelity: simple parent-name heuristic vs the marker-path approach.~~
  **Decided:** shipped the heuristic (`.env`-sourced only) as "just enough" to
  close the bug without the marker-path churn. The heuristic's gaps — it won't
  heal a *moved* worktree, and it can't tell a user's hand-set `.env` value that
  happens to equal the parent name from an inherited one — are covered by the
  `setup --force` escape hatch. Revisit marker-path if those gaps bite.
- Should dox auto-edit `.gwt` (`install-hooks`), or only document the hook and let
  the project add it? Auto-edit mirrors the existing `.env` managed-pin pattern.
- `.gwt` schema details: option-flag passing convention (env vars vs appended
  flags), mutually-exclusive option groups, and whether `scrub` belongs in `.gwt`
  or is subsumed by the engine self-heal.
