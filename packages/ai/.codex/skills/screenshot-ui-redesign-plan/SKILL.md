---
name: screenshot-ui-redesign-plan
description: Turn a screenshot or visual complaint about an existing UI into a grounded redesign plan. Use when the user provides a screenshot, says a UI is bad, asks what is wrong with a screen, wants a redesign plan for a product surface, or wants acceptance criteria to prevent superficial agent-generated UI changes.
---

# Screenshot UI Redesign Plan

## Goal

Use a screenshot as evidence, then inspect the real repo and product context before writing a redesign plan. The output should identify what is wrong, what backend/frontend constraints are real, what layout should replace it, and how the final implementation will be visually verified in a browser.

## Workflow

1. Inspect the screenshot first.
2. Find the route/component/test/docs that own the screen.
3. Read local agent guidance before UI work.
4. Ground claims in source code, docs, tests, and available runtime behavior.
5. Write or update a plan under the repository's planning-doc convention.
6. Include concrete layout requirements, not just principles.
7. Include browser screenshot acceptance gates.

Do not delegate unless the user's prompt or active instructions explicitly authorize orchestration.

## Screenshot Critique

Call out specific visible failures. Cover at least:

- Concept mismatch: what the page claims to be versus what it actually enables.
- Visual hierarchy: what dominates, what should dominate, and where the primary action is.
- Layout mechanics: split attention, dead space, cramped controls, hidden controls, scrolling problems.
- Interaction model: whether the user can act directly on the object they are editing.
- Copy and terminology: product language versus implementation jargon.
- Workflow state: whether status, blockers, review, and next action are obvious.
- Accessibility: contrast, target size, headings, focus, keyboard path, readability.
- Risk/compliance signaling: whether safety language is meaningful or decorative.

Be direct. Do not soften a bad UI into generic observations. Avoid vague phrases like "could be improved" unless followed by a concrete failure and fix.

## Repo Grounding

Search before writing the plan.

Use `rg`/`rg --files` to locate:

- Visible text from the screenshot.
- Route/component files.
- Style files.
- Existing tests/E2E flows.
- Product/architecture/compliance docs that constrain the surface.
- Backend/API/use-case files that determine whether the desired UI can be implemented.

For UI work, read local UI guidance such as `AGENTS.md`, `views/AGENTS.md`, and any UI crate guidance before proposing component changes.

Separate findings into:

- Known implemented backend/frontend capability.
- Missing backend capability.
- Missing validation or test proof.
- Product/design ambiguity that truly cannot be resolved from repo context.

Do not leave "open questions" that can be answered by reading the repository.

## Plan Document Requirements

Place the plan where the repository convention says planning docs live. If unsure, inspect existing docs directories first.

The plan should include:

- Status, owner, and created date.
- Problem statement tied to the screenshot and route.
- Current implementation files and tests.
- "What is wrong" section with concrete numbered failures.
- Repository findings and resolved scope.
- Redesign principles.
- Target user flow.
- Concrete information architecture.
- Implementation slices.
- Testing, systems-test proof, and visual QA.
- Resolved questions and real remaining unknowns.
- Definition of done.

Prefer implementation slices that are small enough to execute. Do not mix "make it prettier" with backend provenance, validation, or workflow changes unless the dependency is explicit.

## Concrete Layout Requirements

Plans for a UI rebuild must specify the new layout. Include:

- Desktop structure.
- Tablet/mobile behavior.
- Above-the-fold requirements.
- Primary and secondary action placement.
- What each region contains.
- What each region must not contain.
- Selected-object behavior.
- Empty, loading, error, dirty, saved, published, blocked, and success states.

For builder/editor UIs, require an object-canvas-inspector model unless the repo's design system clearly uses another stronger pattern:

- Library or navigation rail for saved objects and versions.
- Dominant center canvas where the user sees and selects the thing being built.
- Contextual inspector that changes based on the selected form/section/field/item/state.

Include a simple text wireframe when it would reduce ambiguity.

## Acceptance Criteria

Require automated proof and visual proof.

Automated proof:

- E2E/browser test for changed UI behavior.
- Systems test for behavior changes that hit the real runtime path.
- Targeted project checks, WASM checks for browser-facing Rust/Dioxus changes, and formatting/module checks per repo guidance.

Visual proof:

- Open the real local route in a browser, not a static mock.
- Capture a desktop screenshot at a meaningful width.
- Capture a screenshot of the core interaction state, such as selected field plus inspector.
- Capture a responsive screenshot or explicitly document why responsive work is out of scope.
- Include screenshot paths in the final report.
- Treat visual review as an acceptance gate. Passing tests is not sufficient if the screenshot still shows the same failure mode.

Explicitly reject implementations that preserve the old failure mode under new labels.

## Output Style

Write the plan as an actionable engineering/design artifact, not a mood board.

Use concrete language:

- "Replace the right rail with a contextual inspector."
- "Field rows in the preview must be selectable and drive inspector state."
- "Assignment controls must be hidden until a published version exists."

Avoid weak language:

- "Improve the layout."
- "Make it more intuitive."
- "Use better hierarchy."
- "Polish the UI."

If the user asks only for critique, answer with findings and likely fixes. If the user asks for a reusable plan or docs artifact, write the file.
