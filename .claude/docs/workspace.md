# Workspace hygiene — prefer project-local scratch dirs

For temporary files and log output, use a **project-local directory** (`./tmp/`, `./log/`) rather than `/tmp`, `$TMPDIR`, or the user's home dir. Benefits:

- Artefacts are visible in the project tree, easier to find and clean up
- Gitignore them once per repo instead of juggling system paths
- No cross-project pollution (two projects writing to `/tmp/output.log` collide silently)
- Survives shell invocations and terminal sessions

Only use system temp dirs (`/tmp`, `t.TempDir()` in Go, `tempfile` in Python) for genuinely ephemeral single-invocation fixtures — test scaffolding, throwaway subprocesses. Anything you might want to inspect afterward belongs in-tree.

## Setting up tmp/ and log/

If the project doesn't have a `tmp/` or `log/` directory yet, create it with a `.gitkeep` placeholder and commit both:

```bash
mkdir -p tmp log
touch tmp/.gitkeep log/.gitkeep
```

Then add to `.gitignore`:

```
tmp/*
!tmp/.gitkeep
log/*
!log/.gitkeep
```

This keeps the directories present on every clone (so tooling can write to them without an explicit `mkdir` step) while still ignoring the contents. Commit the `.gitkeep` files and the `.gitignore` entries in the same commit.
