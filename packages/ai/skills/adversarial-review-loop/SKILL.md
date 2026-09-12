---
name: adversarial-review-loop
description: >-
  Lean adversarial review and remediation loop. Spawns a single subagent per round
  to inspect, test, and directly fix issues until it gives a greenlight with no concerns.
tools: Bash, Read, Glob, Grep, Edit, Write, Task
---

# Adversarial Review & Remediation Loop

Run a flat, single-subagent review and repair loop on completed work before declaring done

## Protocol

1. **Dispatch Single Review & Fix Subagent**
   - Spawn a single subagent with write and bash permissions. Choose an appropriate model based on task complexity and needed intelligence
   - Handoff prompt is terse:

     ```text
     Adversarially review the current git diff against the user goal: "<goal>".
     1. Run relevant tests/lint.
     2. Identify any defects, missed requirements, edge cases, or regressions.
     3. Fix all identified issues directly and re-run tests.
     4. Return "GREENLIGHT" if no concerns remain, or report the fixes made and any blockers.
     ```

2. **Evaluate Subagent Report**
   - **`GREENLIGHT` (no issues or concerns remaining)**: Stop. The loop is complete.
   - **Fixes applied**: Re-dispatch the subagent for another pass over the latest diff to confirm no secondary regressions.
   - **Blocker / Ambiguity**: Halt and ask the user for clarification.

3. **Loop Guardrails**
   - Maximum 3 rounds.
   - Stop immediately if the subagent reports zero new defects on its verification pass.
