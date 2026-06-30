# Worktree provisioning — `.env` project-name isolation + `.gwt` hooks plan

**Status:** engine fix landed; `.gwt` hook layer landed. The collision bug
(a worktree inheriting the main checkout's `COMPOSE_PROJECT_NAME`) is closed in
the dox engine via the linked-worktree self-heal plus `setup --force` (step 1
below). The `.gwt` worktree-lifecycle hook layer it motivated (steps 2/3) has
shipped in `dotfiles`: `post-add`/`post-mv`/`pre-rm`/`pre-prune` hooks fire on
`gwt add`/`mv`/`rm`/`prune`, and
`gwt sync` re-provisions an existing worktree (replacing `gwt cp`), `gwt promote`
pushes a worktree's `.worktreeinclude` files back up to root, and `gwt send` copies
one ad-hoc path between any two endpoints (including the lateral worktree→worktree
shuttle). Still open: `dox install-hooks`.

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

The `.gwt` location is overridable with `GWT_FILE` (e.g. `.local/.gwt` for a
project that keeps config out of the repo root), mirroring `DOX_FILE`: resolved
relative to the root, from the shell environment first, then a `GWT_FILE` pinned
in the repo's `.env`, else the default `.gwt`. Only the config file moves — every
operation still keys off the same root and worktree.

```yaml
# .gwt — worktree lifecycle
seed:
  include: .worktreeinclude          # files copied into a new worktree
  scrub:                             # checkout-specific keys stripped from seeded copies
    .env: [COMPOSE_PROJECT_NAME]     # alternative/eager .env fix, declaratively

hooks:
  post-add:   { run: [dox, setup, --force] }   # provision eagerly on create
  post-mv:    { run: [dox, setup, --force] }   # re-point path-derived state after a rename
  pre-rm:     { run: [dox, down] }              # stop the stack before the worktree dies
  pre-prune:  { run: [dox, down] }              # tear down an orphan dir before prune deletes it
  # project example:
  # post-add: { run: [db/bootstrap.py], options: { mode: {values: [read, seed], default: read}, from: {} } }
```

The four events are explicit and independent — none implies another. A `gwt mv`
fires only `post-mv` (a move is a relocation, not a destroy-and-recreate, so it
must not bounce the stack via `pre-rm` or re-seed via `post-add`); a project that
wants the same action on several events declares it under each. A future schema
addition could let one `run:` register for multiple events, and a `version:` field
would only be needed if a key's meaning ever changed incompatibly — neither is
required while every change stays additive.

- **`gwt add <branch> [--seed] [--from main]`** — create, apply `seed`, run
  `post-add` with chosen options.
- **`gwt sync [<name>|--all] [-f] [--hooks]`** — re-provision an existing
  worktree by merging the root's `.worktreeinclude` set back into it (the named
  one, every one with `--all`, or the current one). The merge is rsync without
  `--delete`: add missing, refresh stale, never prune the worktree's own
  untracked files. Default uses `--update` so a locally-newer copy survives; `-f`
  makes root authoritative; `--hooks` re-fires `post-add` after the merge (off by
  default — a plain sync has no side-effects). **Replaces `gwt cp`** —
  re-provisioning declaratively from `.worktreeinclude` is a more meaningful unit
  than pushing one hand-named path. (Named `sync`, not `init`: it reconciles an
  *existing* worktree rather than initialising a new one.) **Shipped.**
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
3. **dotfiles — DONE:** the `.gwt` hook engine (`post-add` on `gwt add`,
   `post-mv` on `gwt mv`, `pre-rm` on `gwt rm`, `pre-prune` on `gwt prune`) plus
   `gwt sync` (replacing `gwt cp`) to re-provision an existing worktree,
   `gwt promote` for the worktree→root direction, and `gwt send` for an ad-hoc
   single path between any two endpoints (including the lateral
   worktree→worktree shuttle).

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
- The reverse direction — all **landed**. **promote** pushes a worktree's
  `.worktreeinclude` files up to root (a separate explicitly-directional verb, not
  a `sync --to-root` flag, since a bidirectional config-set verb risks clobbering
  the canonical copy from a derived one). **send** then covers the ad-hoc
  single-path case in *any* direction — root↔worktree or the **lateral shuttle**
  (worktree→worktree, e.g. `./tmp/`, no config, root uncoupled), file or whole
  directory. All three (`sync`/`promote`/`send`) preview their changes and prompt
  before applying.
