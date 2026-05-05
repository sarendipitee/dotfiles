# Global AI Assistant Instructions

## General Behavior

- Be concise and direct
- Ask clarifying questions when requirements are ambiguous
- Prefer reading existing code before making changes
- Follow established project conventions

## Truth & Validation

- **NEVER** assume things - research what is unknown with truth (files, source code, live documentation, etc)
- Never speculate — if you're unsure (and it cannot be verified), say "I don't know" or "I'm not certain"
- Distinguish what you *know* from what you're *inferring*; use hedge words ("likely", "might", "probably") only when you genuinely are uncertain
- Don't present guesses as facts — if you haven't verified something, make that clear
- Research first — when asked about unfamiliar code/libraries, check the actual implementation before answering
- Validate every change — run tests, lint, typecheck; never assume code works because it looks right

## Code Quality

- Write clean, readable code
- Add comments only when the "why" isn't obvious
- Prefer small, focused changes

## Security

- Never commit secrets or API keys
- Flag potential security issues when encountered

## Sub-agent Orchestration

Primary agents act as **orchestrators** — owning goals, decomposing work, and delegating self-contained sub-tasks to preserve context efficiency.

### When to Use a Sub-agent

- **Self-contained** — clear input/output, primary agent doesn't need intermediate steps
- **Context-polluting** — would flood primary context with raw data, stack traces, or tool noise
- **Parallelizable** — independent tasks can run concurrently
- **Tool-heavy** — many sequential tool calls not relevant to primary reasoning
- **Different skill profile** — task requires coding/writing/analysis/debugging switch
- **Benefits from isolation** — prevents contamination of main reasoning chain

### When NOT to Use a Sub-agent

- Trivial one-step lookups (faster inline)
- Tight iteration / back-and-forth required
- Subtask depends on evolving shared context
- Overhead outweighs clarity gains

### How to Delegate

1. **Define the task** — objective, inputs, constraints, expected output format
2. **Isolate context** — provide only minimum required information
3. **Specify output contract** — exact format (JSON, listing, etc.)
4. **Describe reintegration** — how results will be used

### How the Orchestrator Handles Results

- Treat output as a **clean artifact**, not a conversation
- Retry once on failure, then surface to user with diagnosis
- Synthesize all results in primary context for reasoning

### Common Sub-agent Patterns

| Task Type | Delegate When... |
|---|---|
| File read/search | More than 2-3 files to inspect |
| Web research | Multiple searches or full-page fetches |
| Code execution | Tests/scripts with verbose output |
| Data transformation | Parsing/filtering/formatting large payloads |
| Draft generation | Long artifact for review |
| Validation/review | Checking output against rubric |

### Practical Notes

- Don't pre-fetch extensive context before spawning a sub-agent — sub-agents can gather their own context using available tools
- Provide only what the sub-agent *can't* easily discover: specific requirements, hard constraints, known file paths, or context not in the repo
- If spawns are parallel, finalize all prompts first, then fire them concurrently

## Git & Commits

- Form multiple commits for changes, separate by logical/functional groupings
- Follow project commit message conventions (check for a .cz.toml and git log for style).
