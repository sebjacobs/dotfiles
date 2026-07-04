---
name: cut-release
description: Cut a new release for a repo that publishes on a pushed `vX.Y.Z` tag (goreleaser or similar). Works out the semver bump from the commits since the last tag, then creates and pushes an annotated tag via the GitHub API and watches the release workflow. Use when asked to "cut a release", "tag a release", "ship a new version", "release <repo>", or bump a published tool's version.
---

# Cut a release

For repos whose release is triggered by pushing a `v*` tag — a goreleaser
`on: push: tags: "v*"` workflow that builds, signs, publishes the GitHub
release, and updates a Homebrew tap. This cuts the tag only; it does **not**
edit the source, because the tag *is* the version (goreleaser derives it), so
there is no version file to bump.

A pushed tag publishes a release and updates the tap, and is awkward to unpublish
— so **propose the version and wait for the user to confirm before tagging**.

---

## Steps

### 1 — Identify the repo and confirm it is tag-released

Default to the repo in the current directory; take an explicit `<owner>/<repo>`
if the user names one. Confirm the release trigger is a `v*` tag push:

```bash
gh api -H "Accept: application/vnd.github.raw" repos/<owner>/<repo>/contents/.github/workflows/release.yml | grep -A3 'tags:'
```

If there is no such workflow, stop — this skill only cuts tag-triggered releases.

### 2 — Find the last tag and the commits since it

```bash
last=$(gh api repos/<owner>/<repo>/tags --jq '.[0].name')
gh api repos/<owner>/<repo>/compare/$last...main --jq '.commits[].commit.message | split("\n")[0]'
```

If the compare is `ahead_by: 0`, there is nothing to release — say so and stop.

### 3 — Decide the semver bump

From the conventional-commit prefixes of the commits since the last tag:

- any `feat:` → **minor** (`x.Y.0`)
- only `fix:` / `chore:` / `docs:` / `refactor:` / `perf:` / `test:` → **patch** (`x.y.Z`)
- a `!` suffix or `BREAKING CHANGE` in a body → **major** (`X.0.0`); rare pre-1.0, so call it out rather than assume

Propose the version to the user and **wait for confirmation** before tagging.

### 4 — Create and push the annotated tag

Guard against an existing tag, then tag main's HEAD through the API — no checkout
needed. A tag ref created with the user's `gh` token (a PAT/OAuth token, not the
workflow `GITHUB_TOKEN`) does fire the `push`-tag workflow:

```bash
ver=vX.Y.Z
gh api repos/<owner>/<repo>/git/refs/tags/$ver >/dev/null 2>&1 && { echo "$ver already exists"; return 1; }
sha=$(gh api repos/<owner>/<repo>/git/refs/heads/main --jq .object.sha)
tagobj=$(gh api repos/<owner>/<repo>/git/tags -f tag=$ver -f message="$ver" -f object="$sha" -f type=commit --jq .sha)
gh api repos/<owner>/<repo>/git/refs -f ref=refs/tags/$ver -f sha="$tagobj" --jq .ref
```

### 5 — Watch the release workflow and verify

```bash
gh run watch --repo <owner>/<repo> \
  "$(gh run list --repo <owner>/<repo> --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Confirm it succeeds and the release (plus any tap bump) landed. If the tool is
installed via Homebrew, `brew upgrade <tool>` to pick it up, then verify the new
version actually resolves whatever prompted the release.
