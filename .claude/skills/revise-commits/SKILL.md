---
name: revise-commits
description: Revise, reword, squash, reorder or split the commits on a feature branch so the history reads as a deliberate story before it is shared. Use when the user says "/revise-commits", "tidy the commits", "clean up the history", "reword that commit", "squash the fixups", "the commit message is wrong", "rewrite the branch", or before raising a PR / before merging when the branch carries fixup, WIP or badly-described commits.
---

# Revise commits

Your working history is a draft. Before a branch is shared — and again before it merges, in case review triggered fixups — the commits should read as one deliberate story: each with a single reason to exist, each with a message that explains *why*.

This skill covers rewriting **your own unmerged branch**. It does not cover anything already on `main`.

## Stop before you start

Rewriting history is destructive and easy to do to the wrong commits. Check all four:

1. **Is every commit unmerged and yours?** `git log main...HEAD --oneline`. Anything reachable from `main` is off limits.
2. **Is the branch shared?** If someone else may have it checked out, rewriting forces them into a painful recovery. Ask first.
3. **Is the working tree clean?** `git status --porcelain` must be empty. Uncommitted work will be lost or will silently ride along into the wrong commit.
4. **Take a backup ref.** Non-negotiable, and it costs nothing:

```bash
git branch backup/pre-revise-<branch>
```

Everything below is recoverable with `git reset --hard backup/pre-revise-<branch>` while that ref exists. Delete it only once the user has confirmed the result.

## Survey first, then propose

Read the whole history before touching it:

```bash
git log main...HEAD --format='%h %s%n%b%n---'
```

Look for: `WIP` / `fixup!` / `squash!` / `tmp` subjects, `DO NOT MERGE:` commits that must be dropped entirely, commits describing the *what* with no *why*, several commits that are really one change, one commit that is really several, and messages whose claims the diff no longer supports.

**Propose the target history and wait for approval before rewriting.** Show it as the `git log --oneline` you intend to end up with. The user's sense of what belongs together beats yours.

## Mechanics — no interactive rebase

`git rebase -i` and `git add -i` are unavailable in this environment. Two techniques cover everything.

**The last commit only** — amend in place:

```bash
git commit --amend -F - <<'EOF'
<new message>
EOF
```

**Anything earlier** — rebuild the branch by cherry-picking onto a fresh base. This one technique handles reword, squash, reorder and drop uniformly:

```bash
git checkout -b <branch>-clean $(git merge-base main <branch>)
git cherry-pick <sha>                          # keep as-is, message and all
git cherry-pick <sha> && git commit --amend -F - <<'EOF'
<new message>
EOF
git cherry-pick --no-commit <sha1> <sha2>      # squash a group...
git commit -F - <<'EOF'                        # ...into one commit
<new message>
EOF
```

Pick in chronological order, oldest first — out-of-order picks produce conflicts that would otherwise have been clean.

**Conflict during a `--no-commit` pick:** do **not** run `git cherry-pick --continue`, which finalises that pick as its own commit and breaks the squash. Resolve, `git add` the files, and let the remaining picks run; commit once at the end.

Splitting one commit into several is the same rebuild with `git cherry-pick --no-commit <sha>`, then `git reset` to unstage and commit the pieces separately with `git add <paths>`.

See `~/.claude/docs/git_practices.md` for the branch-triage variant of this recipe.

## Verify before you swap the branch over

**For a message-only revision the tree must be byte-identical.** This is the check that catches a dropped or mangled commit:

```bash
git diff <branch> <branch>-clean          # MUST be empty
git log <branch>-clean --oneline
```

If that diff is non-empty and you only meant to reword, something went wrong — reset and start again rather than reasoning about it. When the revision deliberately drops or splits commits the diff won't be empty, so verify against the intent instead: same file list, expected content changes only.

Then move the branch over and clean up:

```bash
git checkout <branch> && git reset --hard <branch>-clean
git branch -D <branch>-clean
```

Re-run the test suite afterwards if commits were squashed, reordered or split — the intermediate trees are new and may not build even when the final tree is unchanged.

## Pushing a rewritten branch

```bash
git push --force-with-lease origin <branch>
```

**Always `--force-with-lease`, never `--force`** — the lease is what refuses to overwrite work someone else pushed while you were rewriting. Never force-push `main`.

## Message style

Match the repo. **Skim `git log` first and mirror the structure, tone and length of recent commits** — the rules in `~/.claude/CLAUDE.md` are the default, not an override for a repo with its own voice. Sample a handful, not one; the rarest variant is as easy to land on as the common one.

The shape those rules ask for, briefly:

- **Subject:** `<tag>: <Capitalised imperative summary>`, under 72 chars, describing the *value* not the implementation. Tags: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `perf`.
- **Body:** flowing first-person prose covering **why** it was needed, **what it unlocks**, and the **trade-offs / what was consciously left out**. Not a restatement of the diff — the diff already says what changed.
- **Headers earn their place on longer commits.** A short single-idea commit stays plain prose. Note that commit bodies and PR descriptions diverge here in practice: commits tend to open with `** Background **`, PR descriptions with `**Motivation**`. Check which the repo uses before assuming.
- **Every reference carries a URL or commit SHA.** Naming a doc, issue or earlier commit without one is dead weight to a future reader.
- End with the `Co-Authored-By:` trailer naming the actual model.

**Ask when the motivation isn't recoverable.** A commit message invented from the diff is worse than the terse one it replaced — it reads authoritative and may be wrong. If the session log and the code don't tell you *why*, ask rather than guess.

## When not to bother

A branch of one or two well-described commits doesn't need this. Rewriting has real cost and real risk; reach for it when the history would actively mislead a reviewer or a future bisect, not to make a tidy log tidier.
