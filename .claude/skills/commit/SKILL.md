---
name: commit
description: Group finished work into atomic commits and write their messages in the house style — conventional-commit subject, first-person prose body covering why, benefit and trade-offs, linked references. Use before every `git commit`, whether the user asked ("commit", "commit this", "commit that") or you are committing finished work on your own initiative, and whenever you write or check a commit message.
---

# Commit

Commit finished work yourself, without asking first, then list the commits in your report. Commits are local and cheap to regroup or reword, so the user can ask for changes afterwards. Never commit straight to `main` for non-trivial work: branch first (`git checkout -b feature/<name>`). Small self-contained changes (a typo, a doc tweak, a one-line config change) can go straight to `main`. When in doubt, ask.

## Group the changes

1. `git status` and `git diff --stat` to survey everything dirty.
2. Pick a grouping. No need to wait for approval.
3. Stage and commit each group in turn.

Rules:

- **Atomic.** Each commit has one reason to exist. If you can describe it with "and", split it. It should be revertable on its own without breaking anything.
- One commit per logical change — not per file, not one big "various changes" commit. A change that touches several files goes in one commit.
- Unrelated changes go in separate commits.
- Leave unrelated dirty files that were there before you started out of your commits, and mention them.
- Don't commit a half-done step. The work should be finished and the tests green.

**One "commit" approval covers everything proposed.** When the user says "commit" after a grouping was proposed, commit every group in that turn without pausing to re-confirm or report between them. If the proposal flagged optional extras, include them.

**Throwaway commits get a `DO NOT MERGE:` prefix.** Anything on the branch only to exercise CI, reproduce a bug or prove a point — a deliberately failing test, a temporary `puts` — is marked so pre-merge cleanup can't miss it.

## Write the message

**Skim `git log` first and mirror the structure, tone and length of recent commits.** Sample a handful, not one. A repo's own voice wins over the defaults below.

**Subject:** `<tag>: <Capitalised imperative summary>`, under 72 characters in all, describing the *value*, not the implementation. Tags: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `perf`. E.g. `refactor: Move manufacturer list into a config YAML`.

**Body:** flowing first-person prose giving the reasoning the diff can't. It must cover:

- **why** the change was needed — the problem behind it;
- **what it unlocks**;
- **the trade-offs** — why this approach, and what was consciously left out;
- anything that isn't obvious from reading the code.

These are a content checklist, not labels: don't write `Why:` / `Benefit:` / `Trade-offs:`. Don't enumerate the changes either; the diff already does that. A body that only describes what changed is incomplete.

**If the motivation isn't clear from context, ask before writing the message.** A message invented from the diff reads authoritative and may be wrong.

**Headers on longer bodies.** Group the prose under the repo's headers rather than one long block. The house style is ascii-underlined bold: `** Background **`, `** Summary **` / `** Key Changes **`, `** Things to note **`, `** Out of scope **`. Short single-idea commits stay plain prose.

**References carry a URL or commit SHA** — issues, PRs, docs, research, Claude session URLs, earlier commits. Naming one without a link is dead weight. Use footnote markers (`[1]`, `[2]`) in the prose with the links collected at the foot.

**End with the attribution trailer** naming the model you are actually running on: `Co-Authored-By: Claude <model> <noreply@anthropic.com>`, plus any other attribution lines the session asks for.

**Pass the message with a HEREDOC:**

```bash
git commit -F - <<'EOF'
docs: Explain why the cache lives under XDG_CACHE_HOME

...
EOF
```

## Check before committing

- Finished, tests green?
- Smallest unit that delivers value on its own, with one reason to change?
- Unrelated changes split out?
- Subject has a tag, an imperative summary of the value, under 72 characters?
- Body covers why, benefit and trade-offs, in the repo's voice?
- Free of the phrases in `~/.claude/docs/writing_voice.md`? Check the subject especially.
- Every reference linked?
- Message passed via HEREDOC?

Rewording, squashing or reordering commits that already exist is `/revise-commits`.
