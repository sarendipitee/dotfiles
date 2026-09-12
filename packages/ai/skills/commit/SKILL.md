---
name: commit
description: "-"
tools: Bash, Read, Glob, Grep, Edit, Write, WebFetch, WebSearch, Question, Task, Todowrite, Plan
---

Form commits for changes related to your work.
Group each commit by fine-grained logical change.
Infer context from diffs about changes and
Use as many commits as necessary, do not be lazy and dump everything into one commit.
Make a valid commit message that follows .cz.toml rules or repo conventions.

**Use `git add` in the same command as `git commit` (atomic, so you don't step on other agents)

## Commit message specificity

The commit subject MUST identify:

1. The concrete subsystem, package, component, or symbol changed.
2. The observable behavior changed or bug fixed.
3. The relevant trigger, protocol, or domain concept when applicable.

Use this pattern:

`[scope] <type>: <component> <behavior>`

Good:

- `[lib] 🐛 fix: BaseBrokerClient HTTP-date Retry-After parsing`
- `[backend] 🐛 fix: marketdata symbol search database selection`
- `[frontend] ✨ feat: strategy editor indicator parameter validation`

Bad:

- `[lib] 🐛 fix: improve date handling`
- `[misc] 🐛 fix: resolve issue`
- `[backend] ♻️ refactor: update logic`
