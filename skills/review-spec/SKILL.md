---
name: review-spec
description: Review and approve pending spec implementation plans. Lists plans awaiting approval, shows details, and lets you approve or reject.
---

# Review Spec Plans

This skill helps you review implementation plans that were auto-generated from spec files dropped by other Claude agents.

## Workflow

When you run `/review-spec`, I will:

1. **List pending plans** - Show all specs with generated plans awaiting your approval
2. **Let you select one** - Pick which plan to review
3. **Show the full plan** - Display the implementation plan and AI peer review
4. **Get your decision** - Approve, reject, or request modifications

## Commands

### List Pending Specs
```
/review-spec
```
Lists all specs with plans awaiting approval.

### Review Specific Plan
```
/review-spec <plan-id>
```
Shows details for a specific plan.

### Approve and Implement
```
/approve-spec <plan-id>
```
Approves the plan and begins implementation.

### Reject Plan
```
/reject-spec <plan-id> "reason"
```
Rejects the plan with a reason. The original spec can be modified and re-processed.

## Files

- **Spec Registry:** `~/.claude/.spec-registry.json`
- **Generated Plans:** `~/.claude/.spec-plans/`
- **Project Specs:** `<project>/.claude-specs/`

## Reviewing a Plan

When reviewing a plan, check:

1. **Implementation Steps** - Are they complete and in the right order?
2. **AI Peer Review** - Address any concerns raised
3. **Risk Assessment** - Are risks acceptable?
4. **Acceptance Criteria** - Clear and testable?

## After Approval

Once you approve a spec:

1. The plan is marked as "approved" in the registry
2. I will begin implementing according to the plan
3. Each step will be executed with your visibility
4. You can pause implementation at any time

## Spec File Format

Specs should be in `<project>/.claude-specs/` with naming `*-SPEC.md`:

```markdown
---
title: Feature Name
from: agent-name
priority: high|medium|low
project: /path/to/project
---

# Feature Name

## Summary
Brief description.

## Requirements
- Requirement 1
- Requirement 2

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```
