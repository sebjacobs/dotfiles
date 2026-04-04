# Evaluating global and project config changes

Before merging a change to `CLAUDE.md`, `~/.claude/docs/`, or project skills, run a quick A/B eval to verify the change improves agent responses rather than just adding noise. This takes ~5 minutes and catches regressions before they land on main.

---

## When to run an eval

- Adding a new section to CLAUDE.md (principles, workflows, checklists)
- Adding a new file to `~/.claude/docs/` or `docs/engineering/`
- Significantly rewriting an existing section
- Removing content that was previously available
- Moving content from project CLAUDE.md into global CLAUDE.md or `~/.claude/docs/` — verify the project doesn't lose coverage
- Extracting a workflow into a skill — verify the skill produces equivalent or better answers than the inline instructions did
- Creating or updating an agent definition — verify the agent handles its task correctly under the new instructions

Skip it for: typo fixes, formatting changes, adding a link.

---

## The pattern

### Step 1 — write a representative test question

Pick a question that directly exercises the changed content. It should be specific enough that you can judge whether the answer is complete and correct.

Good questions:
- "I've just finished a feature — what should my commit messages look like?" (tests git conventions)
- "I have a messy 20-commit branch — how do I clean it up before raising a PR?" (tests branch triage runbook)
- "I'm starting a new session — walk me through the setup." (tests session skills)

Bad questions (too broad, can't judge completeness):
- "Tell me about the project"
- "How do I write good code?"

### Step 2 — spawn two parallel subagents

**Setup A (baseline — old setup):**

```
Read ONLY [the files that existed before your change]. Do not read any
other files.

Then answer: "[your test question]"

Give a concrete answer based solely on what you found. Note any gaps
where you felt you lacked enough context.
```

**Setup B (new setup):**

```
Read [the files that will exist after your change, including new ones].

Then answer: "[your test question]"

Give a concrete answer based on what you found. Note any gaps.
```

Both agents get the same question. Launch in parallel.

### Step 3 — run an Opus eval agent

Pass both responses and this scoring prompt to an Opus subagent:

```
You are evaluating two setups for a developer assistant:
- Setup A (baseline): agent had access to [old files]
- Setup B (augmented): agent had access to [new files]

Score each response on:
1. Completeness (0–3): did it cover all key points?
2. Accuracy (0–3): was anything wrong, missing, or contradictory?
3. Actionability (0–3): could a developer follow the advice without
   needing to look elsewhere?
4. Gaps acknowledged (0–3): did the agent honestly flag what it
   couldn't answer? (higher = fewer unexplained gaps)

[paste Setup A response]
[paste Setup B response]

Score all four criteria for each response, give totals, and a
2-sentence verdict on which setup performed better and why.
```

Use `model: "opus"` — the scoring judgements are non-trivial.

### Step 4 — interpret the results

| Score delta | Interpretation |
|---|---|
| +3 or more | Clear improvement — merge |
| +1 to +2 | Modest improvement — worth merging if the content is otherwise correct |
| 0 | Neutral — question whether the change is needed |
| Negative | Regression — investigate before merging |

The margin from the git_practices.md eval was +2 (19 → 21 out of 24). The new content improved actionability and depth but didn't fix errors, which is typical for additive docs changes.

**Watch for:** Setup B scoring lower on "gaps acknowledged" than Setup A. This isn't always bad — fewer gaps is the goal — but if Setup B is confidently wrong rather than honestly uncertain, that's a problem.

---

## Worked example — git_practices.md (2026-04-04)

**Change:** added `~/.claude/docs/git_practices.md` (FutureLearn post + branch triage runbook)

**Test questions:**
1. "What should my commit messages look like, and what should I check before raising a PR?"
2. "I have a 20-commit branch with mixed concerns — how do I clean it up?"

**Results:**

| Criterion | Q1 A | Q1 B | Q2 A | Q2 B |
|---|---|---|---|---|
| Completeness | 2 | 3 | 2 | 3 |
| Accuracy | 3 | 3 | 3 | 3 |
| Actionability | 2 | 3 | 2 | 3 |
| Gaps acknowledged | 2 | 1 | 3 | 2 |
| **Subtotal** | **9** | **10** | **10** | **11** |

**Total: 19 vs 21.** Setup B won on depth and actionability — the bucket taxonomy and runbook turned abstract rules into followable procedures. The margin was modest because CLAUDE.md already had the rules; the docs added the *how to apply them* layer.

**Verdict from Opus:** "Setup B performed better overall because the supplementary document gave it concrete examples, a structured taxonomy for branch cleanup, and practical edge-case tips. The margin is modest because Setup A already captured the rules accurately — Setup B's advantage is depth and actionability rather than correcting errors."

---

## Tips

- **Run two questions in parallel, not one.** A single question can produce a lucky answer. Two questions across different aspects of the same change give a more reliable signal.
- **The baseline must be genuinely constrained.** Tell the baseline agent explicitly not to read new files — otherwise it may find them anyway and the comparison is meaningless.
- **Rerun if the margin is close.** LLM responses have variance. If the delta is ±1, run a third question on a different aspect before deciding.
- **The rubric is a starting point.** For domain-specific changes (e.g. a new SQL querying pattern), add a criterion that directly measures whether the agent can apply the new knowledge correctly.
