---
name: gascity-formula-launch
description: "-"
---

# Create and Launch gascity Formula Beads

Use this skill when the user wants one or more Gascity beads created and launched through a formula in a particular rig. The user may name the formula, describe a workflow outcome, or supply only a goal. Resolve the correct launch shape, create the right target object, and sling the formula from the requested rig.

## Operating model

- A **bead** is the durable work target. For a new build, it describes the desired outcome.
- A **formula** is the durable workflow graph. It routes work to `gc.*` roles through formula steps, drains, expansions, and fanout/fanin lanes.
- `gc.run-operator` is the standard launcher target. The formula graph—not a worker agent—owns routing of downstream worker/reviewer work.
- A **targeted** formula (`target_required = true`) needs a target bead or convoy. New full-lifecycle builds normally start with a new bead.
- A **targetless** formula is launched with `--formula`; use it only when the formula's documented entrypoint and prerequisite artifacts/metadata fit the request.
- Launch from the target rig's working context. If that is not possible, pass the normal `--rig <target-rig>` selection so `gc.run-operator` resolves to that rig's role.

Do not launch an opaque provider-native subagent workflow in place of a gascity formula. Formula graphs must retain durable bead routing, retries, fanout/fanin, and evidence.

## Procedure

### 1. Resolve the rig and requested outcome

Identify the target rig and whether the user wants:

- a new end-to-end build from an idea or goal;
- a continuation from already-approved artifacts;
- implementation of an existing convoy; or
- a named formula with explicit launch variables.

Treat every independent requested outcome as its own root bead and formula run unless the user explicitly requests a shared workflow or provides an existing convoy. Write each new bead title as a concise, outcome-oriented request. Root beads own the user's intent: problem/outcome, scope, non-goals, known constraints, relevant paths or links, and acceptance signals. The formula's planning stages own derived requirements, technical design, work-item decomposition, implementation, and review evidence. Do not bury essential intent only in formula variables.

### Root-bead fields

Use the `gc bd create` fields that preserve the user's durable intent. This is the useful subset of its interface:

| Field                             | Use it for                                                                              | Guidance                                                                      |
| --------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| positional `<title>` or `--title` | Short, outcome-oriented name                                                            | Always provide.                                                               |
| `-d`, `--description`             | Problem, desired behavior, scope, non-goals, constraints, relevant paths/links          | Use for every non-trivial new formula run.                                    |
| `--acceptance`                    | Observable completion conditions                                                        | Use when the user provides or needs explicit success criteria.                |
| `--context`                       | Concise supplementary operational/contextual details                                    | Use only when it does not belong in the description.                          |
| `--design`                        | User-approved design decisions or immutable technical constraints                       | Do not populate with planning work the formula should perform.                |
| `-t`, `--type`                    | `bug`, `feature`, `task`, `epic`, `chore`, `decision`, `spike`, `story`, or `milestone` | Set when the user intent makes it clear; otherwise retain the default `task`. |
| `-p`, `--priority`                | User-authorized urgency (`P0`–`P4`; default `P2`)                                       | Do not infer priority.                                                        |
| `--repo`                          | Explicit target repository                                                              | Set only to override normal rig routing.                                      |
| `--external-ref` / `--spec-id`    | Existing issue, ticket, or specification linkage                                        | Preserve supplied references.                                                 |
| `--deps` / `--parent`             | Explicit dependency or hierarchy                                                        | Use only when the requested work already has that relationship.               |
| `--metadata`                      | Structured metadata required by a known local convention                                | Never invent application metadata.                                            |

For a substantial description, prefer `--body-file <file>` or `--stdin` over fragile shell quoting. `--body-file -` reads the description from standard input. `--validate` validates the description against the selected bead type; use it when the local project defines required sections for that type.

Never use `--assignee`, `--status`, `--ephemeral`, `--no-history`, `--mol-type`, `--waits-for`, or gate flags for a normal root formula run unless the user explicitly requests that operational behavior or the active formula/workflow requires it.
 
### Convoys and epics

Do not make convoy creation a separate planning decision for ordinary formula launches. A convoy is the implementation container that holds runnable work beads and their dependency graph; it is not the same thing as a formula workflow or a root bead. An epic (`--type epic`) is hierarchy/tracking only, not an execution container.

Choose the launch shape from the work that already exists:

| Situation | Launcher action | Convoy handling |
| --- | --- | --- |
| New outcome; requirements/planning/decomposition still needed | Create one populated root bead and launch the chosen full-lifecycle formula against it. | The formula's decomposition stage creates or adopts the implementation convoy. Do not pre-create child beads, an epic, or a convoy. |
| One bounded, ready-to-implement source change | Create one complete task bead and attach `implement` with `gc sling gc.run-operator <bead-id> --on implement`. | Core automatically creates the one-item input convoy. Do not create it manually or pass `--no-convoy`. |
| Existing implementation convoy from a prior formula run | Sling `implement` or `build-from-convoy` at its convoy ID. | Reuse it. |

The launcher does not manually run `gc convoy create` as part of this skill. Formula decomposition owns multi-item implementation convoys, and core owns the one-item convoy required for `--on implement`. If a user supplies a manually curated bead graph, preserve it and report that it needs a specialized workflow rather than inventing convoy lifecycle behavior here.

Create an epic only when the user wants a durable reporting hierarchy across independently managed work or formula runs. Never add an epic merely to launch a formula, and never use an epic where an implementation convoy is required.

Before creating anything, inspect the target rig's available formula surface:

```sh
gc formula catalog
```

Use the catalog to select a launchable formula. Do not create a bead if the formula is unavailable; report the missing formula/import and the rig configuration that must be fixed. Do not guess a formula name.

Run `gc formula show <formula> --json` only when the selected formula's target type, required variables, defaults, or workflow behavior are not already clear from the request and normal formula metadata. This is intentionally the exception: its JSON includes the complete resolved steps directly, but is a large output block. Use it sparingly, for a specific decision, and inspect only the relevant fields; do not run it routinely for every launch.

### Simple code tasks: attach `implement`; core creates the container

For a small, self-contained source change with an obvious implementation path, skip requirements, planning, decomposition, and review—but do not raw-route the bead directly to `gc.implementation-worker`. Direct routing does not invoke the deployed implementation lifecycle, so it does not guarantee graph-owned worktree preparation, source-anchor result recording, or implementation-artifact validation.

Use the lightweight implementation path when all of these are true:

- one repository/rig and one coherent change;
- the target location and requested behavior are already clear;
- no meaningful architectural/design choice, cross-cutting dependency, or decomposition is needed;
- the user did not request a formal plan or review; and
- one implementation worker can make and verify the change.

Create a complete source bead: title, exact requested change, affected page/file or clear discovery target, user-visible expected result, constraints, and concise observable acceptance checks. For a text change, quote the old and new text when supplied, identify the page or route, preserve formatting/localization/accessibility constraints, and require a rendered-page smoke test when practical. Do not inflate this into a speculative requirements document.

Attach `implement` to the source bead. Core creates the one-item input convoy required by its drain; never create that convoy yourself and never pass `--no-convoy`:

```sh
gc bd create "<concise change>" \
  --type task \
  --body-file <direct-task.md> \
  --acceptance "<observable completed behavior>"
# Capture the emitted bead ID.
gc sling gc.run-operator <bead-id> --on implement \
  --var drain_policy=separate
```

`implement` is the minimal code-change formula: it creates the required one-item input convoy, validates it, drains its member, records implementation evidence, and stops—there is no requirements, planning, decomposition, or review suffix. With `drain_policy=separate`, its item lifecycle invokes `gc gc workspace prepare`, `path`, and `verify-entry` before source reads/mutations; the worker works only in that deterministic convoy-owned worktree. After a clean commit and the task's required verification, it records the exact output with `gc gc workspace record-result`; source-anchor close obtains the exact result and conditionally cleans the workspace. Formula checks validate the implementation summary artifact. The bead itself must specify the behavior-specific tests/smoke checks, because the formula cannot infer them.

This lightweight path deliberately does **not** perform independent review. Add the `review` formula only when the user requests a review or the change merits one; its report is read-only. Escalate to a full build formula when discovery shows the task is not actually bounded, needs requirements/design/decomposition, affects multiple independently executable changes, or reaches a genuine blocked decision. Do not pre-emptively escalate simple work only because a full-lifecycle formula exists.

### 2. Choose the entrypoint

Default gascity entrypoints:

| Available starting point                     | Formula                                                          | Target                                                   |
| -------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------- |
| New idea / desired outcome                   | `build-basic` or another installed methodology build formula     | New bead                                                 |
| Approved requirements                        | `build-from-plan`                                                | Follow the formula's documented target/variables         |
| Approved requirements, plan, and plan review | `build-from-decompose`                                           | Targetless continuation with prerequisite artifact paths |
| Existing implementation convoy               | `build-from-convoy`                                              | Existing convoy or its documented targetless form        |
| Existing implementation evidence             | `build-from-review`                                              | Targetless continuation with prerequisite evidence       |
| Approved convoy; implementation only         | `implement`                                                      | Existing convoy                                          |
| GitHub issue or PR URL                       | `github-issue-triage`, `github-issue-fix`, or `github-pr-review` | Targetless adapter; inspect required inputs              |

Prefer the installed methodology's named build formula when the user requests that methodology. Do not sling an internal `*-base` formula: base formulas define contracts; their concrete children are the operator-facing workflows.

### 3. Inspect variables and workflow behavior

`gc formula show <formula> --json` is the live, resolved source of truth for a formula's target behavior, variables, defaults, and complete workflow steps. Its JSON is large, so invoke it only when needed to resolve a concrete launch decision—not as a routine preflight. Read the relevant fields only:

```sh
gc formula show <formula> --json
```

Use it to determine `target_required`, declared and inherited variables, defaults, and the complete resolved step graph. In particular, inspect `steps` directly to understand stage order, routed role (`metadata.gc.run_target`), checks, expansions, drains, and artifact contracts.

Only inspect installed formula assets when the JSON's resolved graph still leaves an ambiguity that matters to the requested launch:

1. Locate its `<formula>.formula.toml` in the relevant pack's `formulas/` directory.
2. Read the top-level metadata: `formula`, `extends`, `target_required`, `internal`, `[catalog]`, `[vars]`, and `[metadata.gc.methodology]`.
3. Read parent formulas named by `extends` when the source-level rationale or override boundary matters.

Common build variables, passed as `--var key=value`:

| Variable                | Meaning                                                                                              |
| ----------------------- | ---------------------------------------------------------------------------------------------------- |
| `artifact_root`         | Required directory under the target rig for run artifacts. Use a distinct, stable path per root run. |
| `interaction_mode`      | `interactive`, `autonomous`, or `headless`; controls human gates.                                    |
| `review_mode`           | `report`, `agent`, or `interactive`; controls review/fix handling.                                   |
| `drain_policy`          | `separate` for parallel item sessions, `same-session` for serial shared-session work.                |
| `implementation_target` | Rig role for implementation items; default is generally `gc.implementation-worker`.                  |
| `push`, `open_pr`       | Default `false`; set only with explicit user authorization.                                          |
| `max_iterations`        | Bound on implementation/review repair attempts.                                                      |

Do not invent values, assume defaults across unrelated formulas, or pass variables that `gc formula show` does not accept. Preserve formula defaults unless the user specifies a different behavior. Never enable `push` or `open_pr` without positive authorization.

### 4. Create and sling a new-bead build

For each new targeted build:

```sh
gc bd create "<outcome-oriented bead title>"
# Capture the bead ID emitted by the command.
gc sling gc.run-operator <bead-id> --on <formula> \
  --var artifact_root=plans/<stable-work-name>/build
```

Append only inspected, user-authorized variables, for example:

```sh
  --var interaction_mode=autonomous \
  --var review_mode=agent \
  --var drain_policy=separate
```

Use the bead ID returned by `gc bd create`, not the title or a guessed identifier. Keep the target and formula pairing exact: a new full-lifecycle build targets the new bead; implementation-only formulas target the existing approved convoy instead.

### 5. Launch targetless continuations correctly

Targetless formulas are not bead-creation shortcuts. They resume a documented workflow phase and require its named prerequisite artifacts or metadata. Follow the formula's `show` output exactly. The standard shape is:

```sh
gc sling gc.run-operator <formula-or-documented-target> --formula \
  --var artifact_root=<artifact-dir> \
  --var <required-prerequisite>=<path-or-id>
```

For example, a decomposition continuation needs its approved requirements, plan, and plan-review artifact paths. Do not create a new root bead merely to satisfy a targetless formula.

### 6. Confirm the launch

After each sling, report the created bead ID, target rig, formula name, launch variables, and artifact root. State whether the formula is targeted or targetless. If the CLI returns a run ID/status, include it exactly.

For build workflows, artifacts accumulate under `artifact_root` (typically requirements, plans, reviews, implementation evidence, and a final summary). Do not claim completion merely because the sling was accepted; distinguish “launched” from “workflow completed.”

## Failure handling

- Formula absent from `gc formula catalog`: do not create/sling; identify the missing city/rig import.
- `gc formula show` reveals `target_required = true`: create or use the correct bead/convoy target before slinging.
- `gc formula show` reveals required variables: collect them from the user's request or derive only paths/IDs already established by the workflow; otherwise stop and name the missing inputs.
- Wrong rig context: switch to the target rig or use `--rig <target-rig>` before `gc bd create` and `gc sling`.
- Existing run/artifacts: select the documented continuation formula rather than restart from `build-basic`.
- Multiple independent requests: create and sling separate beads/runs; report each mapping.
