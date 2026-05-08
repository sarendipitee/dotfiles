# Global Kilo Agent Instructions

## Subagent Tool Policy

- Prefer built-in tools for file discovery, reading, editing, and review.
- Do not create or edit files with shell commands.
- Do not use `cat` heredocs, `python`, `perl`, `ruby`, `node`, `sed`, `awk`, `tee`, shell redirection, or inline scripts to create or modify files.
- Use shell commands only when an agent explicitly has bash permission and the task requires executing a verification command, build command, test command, or existing project script.
- Never use shell commands as a substitute for built-in file tools.

## Delegation Guidance

- Use narrow specialist subagents only when the task matches their exact description and constraints.
- Use `complex-implementer` for broad, ambiguous, multi-step, debugging, or cross-file implementation tasks.
- `complex-implementer` should itself delegate independent discovery, mapping, log triage, diff summarization, focused test-writing, mechanical edits, verification runs, and review passes to the specialist subagents when that reduces expensive context use.
- Use tiny editing agents only when exact files, behavior, and acceptance criteria are already known.
- Read-only agents must not edit files or fix issues; they return findings for the primary agent or an implementation agent to act on.
