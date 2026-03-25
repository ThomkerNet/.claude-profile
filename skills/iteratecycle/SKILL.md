---
name: iteratecycle
description: Full iterative development cycle — plan, peer review, fix, implement, peer review, document
---

# Iterate Cycle (`/iteratecycle`)

> Plan → Review → Fix → Gate → Implement → Review → Fix → Document

Automates a rigorous development workflow for non-trivial features. Peer reviews use stage-appropriate review types with hard cycle caps to prevent infinite loops.

## Invocation

```
/iteratecycle                  # full cycle with confirmation gate
/iteratecycle --no-confirm     # skip plan approval gate (trust the plan)
/iteratecycle --plan-only      # produce reviewed plan, stop before implementation
```

---

## Phase 0: Scope Lock

Restate the user's request in **one sentence** as your understood goal and list any **assumptions** you're making. If any of these are missing and will materially affect design, ask up to **3 targeted questions** before proceeding — otherwise proceed with assumptions documented:

- Acceptance criteria / expected behaviour
- API/CLI/UI contract changes
- Data model or migration constraints
- Security/privacy constraints

If the task appears **trivial** (< ~50 lines of straightforward, well-understood code), note this and ask: "This looks simple — proceed with full cycle or just implement directly?"

---

## Phase 1: Implementation Plan

Produce a detailed plan with **all of these sections**:

1. **Goal & acceptance criteria**
2. **Non-goals**
3. **Assumptions & unknowns**
4. **Proposed design**
   - Architecture and component responsibilities
   - Key interfaces / function signatures
   - Data model / schema changes
   - Error handling strategy
5. **Step-by-step implementation tasks** (ordered, checkpointed)
6. **Testing strategy** (unit / integration / e2e; specific test cases)
7. **Rollout / migration / rollback**
8. **Observability** (logs, metrics, tracing as relevant)
9. **Risk list**

---

## Phase 2: Plan Review (max 2 cycles)

Run `tkn-aipeer` peer review on the plan:
- `review_type: architecture`

### Findings policy

| Severity | Action |
|----------|--------|
| Critical / High | **Must fix** before proceeding |
| Medium | Fix if it affects correctness, testability, or avoids future churn — otherwise defer with rationale |
| Low / Nit | Log but **do not block** |

**Batch all fixes** into a single updated plan. Then re-review once.

For each finding, mark it: **Fixed / Deferred / Won't fix** with a one-line rationale.

### Cycle cap

- Maximum **2** review/fix cycles (initial review + one re-review)
- If Critical/High findings remain after cycle 2: **STOP** — report the unresolved findings and ask: "I couldn't resolve these issues automatically. How would you like to proceed?"

---

## Phase 3: Confirmation Gate

Present a concise plan summary:

```
## Plan Summary
- [bullet 1]
- [bullet 2]
- [bullet 3-5 max]

## Files to create / modify
- path/to/file.go — reason
- ...

## Notable trade-offs or risks
- ...
```

**Ask: "Proceed with implementation? (y/n)"**

Wait for explicit user approval. Do not write any code until approved.

> Skip this gate if invoked with `--no-confirm`. Stop here if invoked with `--plan-only`.

---

## Phase 4: Implementation

Follow the approved plan. Constraints:

- **No opportunistic refactors** — only changes required by the plan or review findings
- **Tests are required** — implementation is not complete without tests per the testing strategy; if tests are genuinely not feasible, state why
- If plan divergence is required, explain why and note the deviation inline

### Pre-review build check

Before calling peer review, run the relevant build/lint/test commands for the language:

| Language | Command |
|----------|---------|
| Go | `go build ./...` and `go vet ./...` |
| TypeScript | `tsc --noEmit` |
| Python | `ruff check .` or `flake8` / `mypy` |
| Other | Best-effort equivalent |

Fix any compiler/linter errors before requesting AI review. If no tooling is available, skip and note it.

---

## Phase 5: Implementation Review (max 2 cycles)

Run `tkn-aipeer` peer review on the implementation:
- `review_type: bug` — always
- `review_type: general` — if the change is large or touches multiple systems
- `review_type: security` — if the change touches auth, secrets, file paths, input validation, network, serialization
- `review_type: performance` — if the change involves data volume, latency, or hot paths

Apply the same **findings policy** as Phase 2 (Critical/High must fix; Medium conditional; Low/Nit log only).

**Batch all fixes** into a coherent patch. Re-review once.

Same **cycle cap**: max 2 cycles. If Critical/High remain: stop and ask the user.

---

## Phase 6: Documentation & Commit

Before running `/zdoc`, output a brief final summary:

- What changed (bullet list)
- How to test / run
- Any migrations, config changes, or env vars
- Known limitations or follow-up items

### Conditional `/zdoc`

- If **no Critical/High findings remain**: run `/zdoc` automatically
- If **Critical/High findings remain unresolved**: ask — "There are unresolved findings. Run `/zdoc` anyway, or fix them first?"

---

## Phase Tracking

At the start of each response, print your current state:

```
[Phase X: <Phase Name> — cycle N/2]
```

This keeps the workflow auditable and helps recover if the session is interrupted.

---

## Escape Hatches

- User can interrupt at any phase — the skill will not resist
- `--no-confirm` — skips Phase 3 gate
- `--plan-only` — stops after Phase 3 (no implementation)
- If any MCP tool is unavailable, report it and ask whether to continue without that review step
