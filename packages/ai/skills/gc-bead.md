---
name: gc-bead
description: File work beads (tasks, bugs, epics) in Gas Town on saren-aorus, organize them under epics and convoys, and sling them to polecats for pickup. Use when the user wants to create issues or dispatch work into the remote Gas Town system from this machine.
tools: Bash
---

# Gas Town Remote Bead Filing

Gas Town is a multi-agent work system running on **saren-aorus** (the Linux workstation). Work items are called **beads**. You create them with `gc bd create`, organize them with epics and convoys, and dispatch them with `gc sling`.

## SSH Target

All commands run from the Gas Town root on saren-aorus:

```bash
ssh saren-aorus 'cd ~/cities/gastown && <commands>'
```

## Rigs — Where to File

File the bead in the rig whose code would change. Ask: "Which repo would the fix be committed to?"

| Rig       | Prefix | Owns                                         |
| --------- | ------ | -------------------------------------------- |
| `chatehr` | `ch-`  | The Chatehr app (web frontend, backend, API) |
| `gastown` | `ga-`  | The `gc` CLI, agent roles, Gas Town tooling  |

## Bead Types

| Flag      | Use for                                              |
| --------- | ---------------------------------------------------- |
| `-t task` | Concrete work item with a clear done state (default) |
| `-t bug`  | Something broken                                     |
| `-t epic` | Grouping of related tasks — **never sling an epic**  |

---

## Step 1 — Check Existing Convoys

Before creating anything, check what convoys already exist:

```bash
ssh saren-aorus 'cd ~/cities/gastown && gc convoy list'
```

Output shows open convoys with their ID, title, and progress (e.g. `ch-3va  auth-rewrite  2/5 closed`).

**Decide:** Does the new work belong to an existing convoy (same feature, same initiative)? If yes, add to it. If no, create a new one.

---

## Step 2 — Propose and Get Approval

Before creating anything, present the full planned work tree to the user and wait for explicit approval.

Format it clearly in markdown:

```
## Proposed Work

**Convoy:** auth-rewrite *(new)*

**Epic:** Auth rewrite `[chatehr]`
├── Task 1: Scaffold new auth module — *sling immediately*
├── Task 2: Migrate sessions to new module — *blocked by Task 1*
└── Task 3: Remove legacy auth code — *blocked by Task 2*
```

Include for each item:

- Title and rig
- Type (epic / task / bug)
- Whether it will be slung immediately or is blocked (and by what)
- Convoy: existing ID being added to, or new name

Then ask: **"Proceed with creating these beads?"** and wait for confirmation before running any commands.

---

## Step 3 — Organize the Work

### Scenario A: Flat tasks, no ordering needed

Just create tasks and sling them. No epic or convoy required for simple, independent work items.

### Scenario B: Related tasks that need impl ordering → use an Epic

An epic groups related tasks and lets you express which must complete before others start.

**Create the epic first:**

```bash
EPIC=$(gc bd create "Epic: <feature name>" --rig <rig> -t epic --json | jq -r .id)
```

**Create tasks as children of the epic:**

Child task IDs are hierarchical — they look like `ch-568.1`, `ch-568.2`, etc. Capture them the same way.

```bash
T1=$(gc bd create "Task one" --rig <rig> --parent "$EPIC" --json | jq -r .id)
T2=$(gc bd create "Task two" --rig <rig> --parent "$EPIC" --json | jq -r .id)
T3=$(gc bd create "Task three" --rig <rig> --parent "$EPIC" --json | jq -r .id)
```

**Wire implementation order with dependencies:**

Dependencies express "X needs Y to be done first". The syntax is:

```bash
gc bd dep add <blocked> <blocker>   # blocked depends on blocker
```

⚠️ **Critical:** Think "X needs Y", NOT "X comes before Y" — temporal order is backwards.

```bash
# T2 must wait for T1; T3 must wait for T2
gc bd dep add "$T2" "$T1"
gc bd dep add "$T3" "$T2"
```

Only sling tasks that are currently **unblocked** (i.e. have no unmet dependencies). Blocked tasks will be picked up automatically as their blockers close.

### Scenario C: Large initiative spanning multiple epics → use a Convoy

A convoy is a named collection of beads (and epics) that tracks progress for a whole initiative.

**Add to an existing convoy:**

```bash
gc convoy add <convoy-id> <bead-id>
```

**Create a new convoy and add beads to it:**

```bash
CONVOY=$(gc convoy create "<initiative name>" --json | jq -r .id)
gc convoy add "$CONVOY" "$EPIC"
gc convoy add "$CONVOY" "$T1"
# etc.
```

Check convoy progress at any time:

```bash
gc convoy status <convoy-id>
```

---

## Step 4 — Sling Unblocked Tasks

Sling dispatches a task to the polecat agent pool for that rig. Don't set `--assignee` — the pool dispatch requires the assignee to be empty.

```bash
gc sling <rig>/gastown.polecat <bead-id>
```

Examples:

- `gc sling chatehr/gastown.polecat ch-k52`
- `gc sling gastown/gastown.polecat ga-b17`

**Only sling tasks** — not epics, not convoys. Only sling tasks that are unblocked (no pending deps).

---

## Full SSH Command Patterns

### Flat tasks (no ordering)

```bash
ssh saren@saren-aorus 'cd ~/cities/gastown && \
  T1=$(gc bd create "First task" --rig chatehr -t task --json | jq -r .id) && \
  T2=$(gc bd create "Second task" --rig chatehr -t task --json | jq -r .id) && \
  gc sling chatehr/gastown.polecat "$T1" && \
  gc sling chatehr/gastown.polecat "$T2" && \
  echo "Filed: $T1 $T2"'
```

### Epic with ordered tasks, new convoy

```bash
ssh saren@saren-aorus 'cd ~/cities/gastown && \
  EPIC=$(gc bd create "Epic: Auth rewrite" --rig chatehr -t epic --json | jq -r .id) && \
  T1=$(gc bd create "Scaffold new auth module" --rig chatehr --parent "$EPIC" --json | jq -r .id) && \
  T2=$(gc bd create "Migrate sessions to new module" --rig chatehr --parent "$EPIC" --json | jq -r .id) && \
  T3=$(gc bd create "Remove legacy auth code" --rig chatehr --parent "$EPIC" --json | jq -r .id) && \
  gc bd dep add "$T2" "$T1" && \
  gc bd dep add "$T3" "$T2" && \
  CONVOY=$(gc convoy create "auth-rewrite" --json | jq -r .id) && \
  gc convoy add "$CONVOY" "$EPIC" && \
  gc sling chatehr/gastown.polecat "$T1" && \
  echo "Epic: $EPIC | Tasks: $T1 $T2 $T3 | Convoy: $CONVOY"'
```

_(Only T1 is slung — T2 and T3 are blocked and will unlock as work completes)_

### Add to existing convoy

```bash
ssh saren@saren-aorus 'cd ~/cities/gastown && \
  T=$(gc bd create "New task" --rig chatehr -t task --json | jq -r .id) && \
  gc convoy add ch-3va "$T" && \
  gc sling chatehr/gastown.polecat "$T" && \
  echo "Added $T to ch-3va"'
```

---

## Decision Checklist

1. **Run `gc convoy list` first** — know what already exists
2. **Plan the full work tree** — convoy, epics, tasks, deps, what gets slung
3. **Present the tree and wait for approval** — do not create anything until confirmed
4. **Is this work related to an existing convoy?** → add to it; otherwise create new
5. **Do these tasks have a required order?** → create an epic, wire deps with `gc bd dep add`
6. **Sling only unblocked tasks** — blocked ones unlock automatically
7. **Never sling epics**
