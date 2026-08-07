# Writing voice — terms to avoid

Words and constructions that read as machine-written rather than as something I
would say. They turn up in commit subjects, PR descriptions, code comments and
chat, and they survive review because nothing about them is *wrong* — they are
just not how I talk about the change.

This list is evidence-based, seeded by reading six months of my own commit
subjects and merged PR descriptions. **A term earns a place here only if my
history never uses it and I keep having to rewrite it.** See "Words that look
like slop but aren't" at the foot — over-correcting is its own failure.

## How to use this

Before writing a commit subject or a PR paragraph, check the phrase against the
left column. If it matches, say the thing in the right column instead. When
neither fits, look at how a comparable change was described in the repo's own
history — that is the real source of truth, and it beats this table.

## The list

| Avoid | Say instead | Why |
| --- | --- | --- |
| **Hold X to a constant / fixed number of Y** | Name the mechanism: *Preload the associations for each admin card* · *Count the rows once per page, not once per row* | "Hold X to" is a metric-dashboard phrase. I use "hold" in its ordinary sense — a variable *holds* a value, a database *holds* the rule — never as "keep within a limit". |
| **Leverage X** | *Use X* | I have never written "leverage". Precedent: *Use the `peer` variant for the dropdown's clear button*. |
| **Utilise / utilize** | *Use* | Same. |
| **Wire up X** | *Add* · *Register* · *Use* | Precedent: *Register feature flags automatically on deploy*. |
| **Facilitate / enable users to** | *Let* · *Allow* · *Offer* | Precedent: *Allow users to filter search results by category* · *Let admins approve a profile from its form*. |
| **Streamline** | *Simplify* · *Extract* · *Move* | Precedent: *Simplify the notification logic using the new method*. |
| **Harden** | *Guard* · *Validate* · *Pin down* | Precedent: *Pin down that deleting a parent deletes no child*. |
| **Optimise / improve performance** (with no mechanism) | Name what changed: *Memoise the names once in the script* · *Preload the associations* | A perf subject that doesn't say what it did tells a reader nothing. Mine always name the mechanism. |
| **Handle X gracefully** | Say what actually happens: *Keep the children when the parent is deleted* | "Gracefully" is where the behaviour should be. |
| **In order to** | *to* | Three words for one. |
| **Under the hood** | Just describe it | Never appears. |
| **Seamless / effortless / powerful / elegant / battle-tested / production-ready / future-proof** | Drop the adjective | Zero occurrences across the whole corpus. If the thing is good, the diff shows it. |
| **Delve into** | *Look at* · *Read* | Never appears. |
| **Out of the box / best practice / at scale / going forward** | Say the specific thing | Filler that survives deletion untouched. |
| **Significantly / dramatically / greatly faster** | Give the number, or say nothing | One occurrence of "significantly" in six months. If it matters, measure it. |
| **Solidify / cement / bolster / safeguard / orchestrate** | *Add* · *Keep* · *Guard* · *Run* | Never appears as a verb for code changes. |
| **Single source of truth / first-class / guard rail** | Describe the mechanism | Consultant vocabulary. |
| **This commit / this PR does X** | Write about the system, not the patch: *The controller now preloads…* | The message is already attached to the commit. |
| **Simply / just / obviously** | Delete | If it were obvious it wouldn't need the message. |

## Subject-line verbs I actually use

In rough order of frequency over six months. When a subject feels off, it is
usually because the verb is not one of these:

> Add · Remove · Make · Give · Use · Extract · Name · Move · Allow · Let ·
> Split · Keep · Stop · Skip · Seed · Normalize · Document · Show · Record ·
> Pin · Cover · Characterize · Validate · Simplify · Replace · Rename · Order ·
> Match · Hide · Guard · Enforce · Drop · Restore

Two patterns worth copying directly:

- **Name a thing for what it is.** *Name the join after what it joins* ·
  *Name the variables for what they hold*.
- **Give an object a responsibility.** *Make the model responsible for exposing
  the related record* · *Hand the views the distance, not the point to measure
  it from*.

## Body prose

My bodies are plain and first person. *"I have wrapped a test around it using
the `count_queries` helper (introduced in the previous commit)."* — that is the
register. Not *"A comprehensive test suite has been introduced to ensure
robust coverage."*

## Words that look like slop but aren't

Do **not** strip these — they are in my own subject lines and rewriting them is
an over-correction:

- **Introduce** — *Introduce a reusable validator* (used often)
- **Ensure** — *Ensure the contact details remain valid*
- **Surface** — *Surface readable errors from the packages action*
- **Robust** — *Make the normalizer more robust*
- **Guard**, **Tidy**, **Clean up**, **Unlock**, **Sanity check** — all in use

## Adding to this list

Add a term when a rewrite happens for the second time, not the first — one
awkward phrase is noise, a repeat is a habit. Every entry needs the natural
alternative beside it; a ban with no replacement just produces a different
awkward phrase. Check the corpus before adding: if the word appears in my own
subject lines, it belongs in the section above, not the table.
