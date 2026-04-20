# Subagents and parallelisation

**Subagents for research + build; background Bash for parallel compute.**

- Use a subagent (general-purpose or Explore) when a task has many exploratory steps — browsing, reading files, writing a script, running it — that would bloat the main context. The subagent does all the work and returns a clean result.
- Use background `Bash` tool calls for parallelising compute work on existing files (e.g. chunked scraping, batch processing). Simpler, no permission overhead.

## Background subagent permission gotcha

Background subagents must have all tool permissions pre-approved at spawn time. Tools not approved upfront are auto-denied at runtime — no prompt is relayed to the user. Three options if a subagent needs `Bash`:

1. **Define a named subagent** in `.claude/agents/name.md` with a `tools:` frontmatter field — Claude Code prompts for those tools upfront before launching: `tools: Bash, Read, Write, Glob`
2. Run it in **foreground** mode (no `run_in_background: true`) so permission prompts come through normally
3. Skip subagents and use background `Bash` jobs directly — they inherit the session's already-approved permissions

**Foreground subagents** relay permission prompts and `AskUserQuestion` calls normally — use these when the task may need interactive permission grants.

## Agent file vs skill file

| | Skill (`.claude/skills/`) | Agent (`.claude/agents/`) |
|---|---|---|
| Runs in | Main context | Isolated subprocess |
| Sees conversation history | Yes | No |
| Invoked by | `/skill-name` or auto-load | Agent tool or `@agent-name` |
| Tool restrictions | `allowed-tools` (additive) | `tools` / `disallowedTools` |
| Output | Stays in conversation | Summarised and returned |

- **Skill** — reusable instructions/playbooks that need conversation context. Use for workflows like `/commit`, `/review-pr`, checklists.
- **Agent** — self-contained work that produces a result and doesn't need conversation history. Use for scrapers, researchers, test runners, batch processors.

Rule of thumb: if the task produces a *result* you hand back → agent. If it needs *context* from the conversation to work → skill.

**One-off scoped agents** (no file needed): pass `--agents '{...}'` JSON at session launch — session-only, no file created, gone when Claude exits. Useful for spike sessions with restricted tool access (e.g. read-only research).

## Partitioning work across parallel subagents

When a task involves making the same change to N files (e.g. adding logging to 16 scripts, updating imports across a codebase), partition the files into groups of 4–6 and launch one background subagent per group. Each agent gets the full pattern/spec plus its specific file list. This is faster than sequential editing and keeps the main context clean. Rules:

- Ensure no file appears in more than one agent's list — parallel writes to the same file will conflict
- Give each agent the reference implementation to read first, so it applies the pattern consistently
- Have agents edit only, no commits — review the diff and commit in the main context once all agents finish
- Use **Haiku** for these agents when the pattern is fully specified — the task is mechanical execution, not judgment

## Model routing — Haiku / Sonnet / Opus

The Agent tool accepts a `model` parameter (`"haiku"`, `"sonnet"`, `"opus"`). Route tasks to the cheapest model that can handle them reliably.

| Model | Use when |
|---|---|
| **Haiku** | High-volume, well-defined execution: classification, structured extraction, filtering/triage, scraping against a documented spec, batch tagging. Task is fully specified — no judgment needed. Add explicit "stop and report back" conditions for unexpected states. |
| **Sonnet** | Default for most tasks: research, coding, multi-step workflows, anything requiring moderate judgment or adaptation. |
| **Opus** | High-stakes reasoning: thesis construction, cross-source synthesis, ambiguous signal interpretation, decisions that affect capital allocation. Use when the output directly informs a buy/sell decision or requires extended reasoning over complex multi-signal inputs. |

**The handoff pattern for Haiku:** Sonnet works out the details (schema, selectors, edge cases), documents them clearly in the agent prompt, then spawns Haiku to execute. Sonnet reviews output and decides next steps. If Haiku hits an unexpected state, it should stop and report rather than retry — build this into the prompt explicitly.
