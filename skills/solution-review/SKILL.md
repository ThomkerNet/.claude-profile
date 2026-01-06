---
name: solution-review
description: Comprehensive review of any project or solution. Breaks code into manageable chunks, evaluates each section, uses Gemini for second opinions, and outputs improvements, suggestions, optimizations, and risks. Use when reviewing a solution, auditing code, or asking for a comprehensive review.
---

# Solution Review

A systematic approach to reviewing any codebase or solution, breaking it into digestible sections and providing multi-perspective analysis.

## Process

### 1. Discovery Phase

First, understand the project structure:

```bash
# Get overview of project structure
find . -type f -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.rs" | head -50
```

Identify:
- Entry points (main files, index files)
- Configuration files
- Core business logic
- Utilities and helpers
- Tests

### 2. Chunking Strategy

Break the project into reviewable sections:

| Section Type | What to Include |
|--------------|-----------------|
| **Configuration** | package.json, tsconfig, .env examples, docker configs |
| **Data Layer** | Database schemas, models, migrations, ORM setup |
| **API Layer** | Routes, controllers, middleware, authentication |
| **Business Logic** | Core services, domain logic, algorithms |
| **Infrastructure** | Build scripts, CI/CD, deployment configs |
| **Testing** | Test files, fixtures, mocks |

### 3. Section-by-Section Review

For each section, evaluate:

#### Code Quality
- Readability and maintainability
- Naming conventions
- Code duplication
- Complexity (cyclomatic, cognitive)

#### Architecture
- Separation of concerns
- Dependency management
- Design patterns used/misused
- Scalability considerations

#### Security
- Input validation
- Authentication/authorization
- Secrets management
- OWASP Top 10 vulnerabilities

#### Performance
- Database query efficiency
- Memory usage patterns
- Caching opportunities
- Async/blocking operations

### 4. Copilot Second Opinion

For each major section, get another model's perspective via Copilot:

```bash
copilot --model gpt-5.1 -p "Review this code section for improvements, risks, and optimizations. Context: [describe what the code does]

Code:
[paste relevant code]

Looking for:
1. Security vulnerabilities
2. Performance issues
3. Code smells
4. Better patterns/approaches
5. Edge cases not handled"
```

**Available models:** `gpt-5.1`, `claude-opus-4.5`, `gemini-3-pro-preview`

### 5. Output Format

Structure findings as:

```markdown
## Section: [Name]

### Overview
Brief description of what this section does.

### Strengths
- What's done well

### Issues Found

| Severity | Issue | Location | Recommendation |
|----------|-------|----------|----------------|
| Critical | ... | file:line | ... |
| High | ... | file:line | ... |
| Medium | ... | file:line | ... |
| Low | ... | file:line | ... |

### Copilot's Perspective
Summary of second opinion insights.

### Optimizations
1. Specific actionable improvements

### Risks
- Potential problems if not addressed
```

## Review Checklist

Use this checklist for each section:

- [ ] Error handling complete?
- [ ] Edge cases covered?
- [ ] Input validation present?
- [ ] Logging adequate?
- [ ] Tests exist and meaningful?
- [ ] Documentation current?
- [ ] Dependencies up to date?
- [ ] No hardcoded secrets?
- [ ] Rate limiting where needed?
- [ ] Graceful degradation?

## Severity Definitions

| Level | Definition | Action |
|-------|------------|--------|
| **Critical** | Security vulnerability, data loss risk, system crash | Fix immediately |
| **High** | Major bug, significant performance issue | Fix before release |
| **Medium** | Code smell, minor bug, maintainability issue | Plan to fix |
| **Low** | Style issue, minor optimization, nice-to-have | Consider fixing |

## Example Copilot Prompts

### Security Review
```bash
copilot --model gpt-5.1 -p "Security review: Look for injection vulnerabilities, auth bypasses, and data exposure risks in this code: [code]"
```

### Architecture Review
```bash
copilot --model claude-opus-4.5 -p "Architecture review: Evaluate coupling, cohesion, and suggest better patterns for: [code]"
```

### Performance Review
```bash
copilot --model gemini-3-pro-preview -p "Performance review: Identify bottlenecks, N+1 queries, memory leaks in: [code]"
```

## Final Summary Template

After reviewing all sections:

```markdown
# Solution Review Summary

## Overall Assessment
[1-2 paragraph summary]

## Critical Issues (Fix Immediately)
1. ...

## High Priority Improvements
1. ...

## Quick Wins
1. ...

## Technical Debt
1. ...

## Model Consensus
Key points where reviewers agreed.

## Differing Opinions
Areas where perspectives differed (investigate further).

## Recommended Next Steps
1. ...
2. ...
3. ...
```
