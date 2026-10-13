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
1. Run relevant tests/lint/checks.
2. Identify any defects, missed requirements, edge cases, or regressions.
3. Fix all identified issues directly and re-run tests.

If issues were found and fixed: Stop and report to parent.
If issues were found but could not be resolved or you deem it requires stakeholder input/clarification: Stop and report to parent.
If no issues were found and no code changes were made and all relevant checks are green: report GREENLIGHT

Important: DO NOT LOAD ANY SKILLS. DO NOT HAND OFF YOUR TASK TO A SUBAGENT. YOU _ARE_ THE SUBAGENT.
```

1. **Evaluate Subagent Report**
   - **`GREENLIGHT` (no issues or concerns remaining)**: Stop. The loop is complete.
   - **Fixes applied**: Re-dispatch the subagent for another pass over the latest diff to confirm no secondary regressions.
   - **Blocker / Ambiguity**: Halt and ask the user for clarification.

2. **Loop Guardrails**
   - Maximum 4 rounds.
   - Stop immediately if the subagent reports zero new defects on its verification pass.

## Notes

- Agents failing to respond to complete is NOT a blocker. That is YOUR problem to solve by relaunching an agent.
- However, give subagent plenty of time to complete its task. Mark the current time when the subagent was started and do not ask for a report after only a few minutes. Check that it is making progress only after 10m if you have that capability.
