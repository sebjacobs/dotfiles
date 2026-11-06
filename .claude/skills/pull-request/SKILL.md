---
name: pull-request
description: Write, raise or edit a pull request — the description template, matching the repo's house style, editing a live PR body in place, adding screenshots, and the Forgejo `fgj` flags that differ from `gh`. Use whenever you are about to run `gh pr create`, `fgj pr create`, `gh pr edit` or `fgj pr edit`, write or update a PR description, issue body or PR comment, attach screenshots to a PR, or when the user says "raise a PR", "open a PR", "write the PR description", "update the PR".
---

# Pull requests

Opening or editing a PR is outward-facing: only do it once the user has said to. This skill covers how, once they have.

## Which remote, which CLI

Check `git remote -v` first. Personal projects use the self-hosted Forgejo as `origin` and GitHub (the `gh` remote) only as a mirror — PRs go on `origin`, never on GitHub. Work and client repos have GitHub as `origin` and use `gh`.

On Forgejo, use `fgj` in place of `gh`. It reads the repo from `origin`, but the flags differ:

- `fgj pr create` has no `--body-file` — pass `--title "…" --body "$(cat body.md)"`. `fgj pr edit` does take `-F/--body-file`.
- `--json` takes no field list and there is no `--jq`; pipe to `jq`, e.g. `fgj pr view <n> --json | jq -r .body`.
- For anything without a command, `fgj api repos/<owner>/<repo>/…` makes an authenticated call. It does not fill in owner and repo for you.

Check `fgj <cmd> --help` before using a flag you haven't seen work. Never fall back to `curl` with a pasted token.

## Before raising

Review every commit with `git log main...<branch> --oneline`. Fixup, rename and "oops" commits get squashed into the commit they belong with (`/revise-commits`), and throwaway `DO NOT MERGE:` commits get dropped. If unrelated changes crept in, split them onto their own branch first.

## Writing the description

**Read the repo before writing the template.** A repo with an established PR style wins over anything here — skim the last handful of *merged* PRs (`gh pr list --state merged --limit 15 --json number,body`) and mirror their headings, tone, and **length**. The template below is the default for a repo with no convention of its own, and it is also what a house style tends to converge on. Getting this wrong is easy and invisible: copying the format of one recent PR is a sample of one, and the rarest variant is as likely to be the one you land on as the common one.

PR descriptions follow the same philosophy as commit messages — explain the *why*, not just the *what*, and **defer the per-change detail to the commit messages** rather than re-narrating the diff. The body orients the reviewer; the commits carry the specifics.

**Keep it short.** A PR description that is longer than any recently merged one is a signal you are re-narrating the diff. Match the repo's range; when in doubt, aim for the middle of it, not the top.

**Check the wording against `~/.claude/docs/writing_voice.md`** — the phrases that read as machine-written, each with the natural alternative beside it, plus the words that look like slop but are genuinely in use. A PR description is read by people who did not write the branch, so an off-key phrase is more noticeable here than anywhere else.

Structure — three sections, bold-with-underline headings:

1. **Motivation** — lead with the *why*, kept high-level: a paragraph or two on the problem this solves or the capability it unlocks, and the reasoning behind the approach. Don't enumerate the changes here. Illustrate the problem with one concrete example rather than listing every instance of it. For a stacked or part-N PR, open by naming the part it follows and linking it. If the PR is behaviour-preserving except for a deliberate change, call that exception out here.
2. **Summary** — open with **one or two sentences of plain English on the impact**, set in bold, before any bullet: what is actually different now, in terms a reader who did not write the branch would care about. Not a restatement of the title, not an inventory of the parts — the effect. E.g. *"System tests no longer touch the network. The browser gets every third-party file from disk instead of from someone else's CDN, which halves the suite's runtime and takes an outage or a slow response off the list of things that can turn a build red."* The bullets say what was built; this says what it buys, and it is the part a reviewer skimming the list of open PRs actually reads. Then a short bullet list of the significant changes at a high level (not exhaustive, not file-by-file). End with **"See individual commit messages for the details."** Fold references inline where they belong (every reference carries a URL or commit SHA). For a stacked PR, close with a line naming the base branch and a compare link, plus the merge/rebase order. **Don't link to predecessor/draft PRs as predecessors** — but part-N cross-links between live stacked PRs are the point, keep those.
3. **Things to note** — gotchas, trade-offs, deliberate omissions, anything that would surprise a reviewer reading the diff cold. One idea per bullet. This is where scope boundaries and "what this deliberately does not do" live.

**Questions for the reviewer go in Things to note, not their own heading** — phrased as the decision you took plus an invitation, e.g. "I went narrow rather than wide because X. Shout if you'd rather go wide." Still raise them: a judgement call left unflagged is a judgement call nobody reviews.

Do **not** add separate `Key changes`, `Gotchas`, `References`, `Out of scope`, or `Test plan` headings. Skip a `TODO` checklist unless the branch genuinely has outstanding steps worth tracking in public — an empty-by-merge-time checklist is noise. If the project tracks work in an issue tracker, the task link goes on the first line, above everything.

Example:

```markdown
https://tracker.example.com/task/1234

**Motivation**
============

Part 1 (#41) taught the client to read the API's ETag headers. This branch uses them
to cache responses on disk, so a repeated `list` no longer goes back to the server for
data it already has.

The cache lives under `$XDG_CACHE_HOME` rather than beside the config, so clearing it
never touches settings. It is on by default; `--no-cache` skips it for a single call.

**Summary**
===========

**Running the same command twice no longer waits on the network the second time, and
the CLI keeps working on a flaky connection for anything it has already seen.**

- Store each response with its ETag and send `If-None-Match` next time. A `304`
  serves the stored copy.
- Fall back to the cached copy, with a warning, when the server can't be reached.
- Add `cache clear`, so a user can start fresh without hunting for the directory.

See individual commit messages for the details.

**Things to note**
===============

- Nothing expires on a timer. The server decides what is stale through the ETag, which
  avoids picking one TTL that is wrong for every endpoint.

- Writes are never cached or replayed. Queuing them offline means resolving conflicts,
  and that is a separate piece of work.

- The fallback serves stale data rather than failing. Every command today is read-only,
  so I went that way. Shout if you'd rather it fail loudly.
```

## Editing a description, issue or comment

**Editing PR descriptions, issues, comments — fetch live state first, edit in place, never regenerate from a remembered template.** The user is often editing the same artifact concurrently in the GitHub UI. Regenerating the whole body from your last-known version silently stomps their edits. The right pattern is always: `gh pr view <n> --json body --jq .body > ./tmp/body.md` → `Edit` only the line that needs changing → `gh pr edit <n> --body-file ./tmp/body.md`. Applies equally to issue bodies, PR comments, anywhere a human and you might both write. If a small targeted edit isn't possible (e.g. major restructure), confirm with the user before pushing a full rewrite.

## Screenshots

Screenshots earn their place when the change is visual — a before/after pair showing
the broken state next to the fixed one does more than a paragraph. Three constraints,
all learned the hard way:

- **`gh` cannot attach images.** `--body-file` is text only, and the endpoint the web
  UI posts to (`/upload/policies/assets`) is session-authenticated, so a token cannot
  drive it. The working flow: ask the user to drag the files into a **comment** on the
  PR and post it, read the `user-attachments` URLs back from the comment with
  `gh pr view <n> --json comments`, build them into the description, then the user deletes
  the comment. The URLs survive the comment being deleted.

- **On a private repo, `raw.githubusercontent.com` URLs do not render.** GitHub's camo
  proxy fetches server-side without the viewer's credentials, so pushing images to a
  side branch and linking them is a dead end — they show as broken images. Do not
  reach for it.

- **Downscale before uploading.** GitHub renders a dragged-in image at its intrinsic
  size, and drag-and-drop inserts plain `![](url)` where you get no say. A desktop
  capture at 2× DPR is enormous. Resize by the DPR factor first
  (`sips --resampleWidth <css-px> shot.png`) — use `--resampleWidth`, not `-Z`, which
  constrains the longest side and leaves inconsistent widths. Mobile-width captures are
  fine as they are; tablet and up need it. Name the files with a zero-padded prefix
  (`01-`, `02-`) so they upload in order.

## DarkReader before any visual check

**Before any browser screenshot or visual check, ask the user to disable DarkReader.**
On client projects the app usually ships no dark mode at all, so DarkReader is showing
a machine inversion of a light-only design: it looks subtly broken, and it hides real
problems with contrast and colour. It cannot be neutralised from the page — removing
its injected style nodes triggers its MutationObserver and they come straight back —
and toggling the extension is a change to the user's browser, not yours to make. So
ask, and wait. Geometry (`scrollHeight`, layout measurements) is unaffected, but
anything judged by eye is not.

## Labels

Don't bother with PR labels — skip `gh label list` and create PRs without a label unless explicitly asked to add one.
