---
name: create-spec
description: Create a spec file to hand off work to another Claude agent. Generates a structured *-SPEC.md file in the target project.
---

# Create Spec

This skill helps you create a specification file that can be picked up and processed by another Claude agent.

## Usage

```
/create-spec <target-project> <spec-name>
```

Or just:
```
/create-spec
```
And I'll ask you for the details interactively.

## What It Does

1. **Gathers requirements** - I'll ask you about:
   - What needs to be implemented
   - Requirements and constraints
   - Acceptance criteria
   - Priority level
   - Any context the receiving agent needs

2. **Creates spec file** - Generates a structured markdown file:
   - `<target-project>/.claude-specs/<spec-name>-SPEC.md`

3. **Registers project** - Ensures the target project is being watched

4. **Notifies** - The spec watcher will detect it and auto-process

## Spec Template

The generated spec will follow this format:

```markdown
---
title: <Title>
from: <current-agent-id>
to: any
priority: <high|medium|low>
created: <ISO timestamp>
project: <target-project-path>
---

# <Title>

## Summary
<Brief description of what needs to be done>

## Context
<Background information, why this is needed, related work>

## Requirements
- <Requirement 1>
- <Requirement 2>
- ...

## Technical Notes
<Any technical constraints, dependencies, or considerations>

## Acceptance Criteria
- [ ] <Criterion 1>
- [ ] <Criterion 2>
- ...

## Related Files
- <file1>
- <file2>

## Notes from Originating Agent
<Any additional context or suggestions>
```

## Examples

### Hand off a feature
```
/create-spec ~/git/webapp "user-authentication"
```

### Hand off a bug fix
```
/create-spec ~/git/api "fix-rate-limiting"
```

### Hand off to current project
```
/create-spec . "refactor-database-layer"
```

## Tips

1. **Be specific** - The more detail in the spec, the better the implementation plan
2. **Include context** - What problem does this solve? Why now?
3. **List related files** - Help the receiving agent find relevant code
4. **Set priority** - Helps agents prioritize when multiple specs exist
5. **Add acceptance criteria** - Clear criteria enable verification

## Watching Projects

To ensure a project is being watched for specs:
```bash
~/.claude/services/spec-watcher/watcher.sh register /path/to/project
```

This creates the `.claude-specs/` directory and adds it to the watch list.
