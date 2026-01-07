# AI Peer Review Command

> **Description:** Smart multi-model code review that selects the 3 best AI models based on review type

**Invoke:** /Users/sbarker/.bun/bin/bun run /Users/sbarker/.claude/scripts/aipeerreview/index.ts

## Usage

```
/aipeerreview [options] [file]
```

## Options

- `-t, --type <type>` - Review type (auto-detected if omitted)
- `-h, --help` - Show help

## Review Types & Model Selection

| Type | Models | Best For |
|------|--------|----------|
| **security** | Opus 4.5, Codex-Max, Gemini 3 | Auth, injection, OWASP vulnerabilities |
| **architecture** | Opus 4.5, Gemini 3, Sonnet 4.5 | Design patterns, scalability, coupling |
| **bug** | Opus 4.5, Codex-Max, Sonnet 4.5 | Logic errors, edge cases, race conditions |
| **performance** | Opus 4.5, Codex, Gemini 3 | Complexity, optimization, bottlenecks |
| **api** | Opus 4.5, GPT-5.1, Sonnet 4.5 | REST design, contracts, versioning |
| **test** | Opus 4.5, Codex-Max, Sonnet 4.5 | Coverage gaps, mocking, assertions |
| **general** | Opus 4.5, GPT-5.1, Gemini 3 | Broad code quality assessment |

## Examples

```bash
/aipeerreview                          # Auto-detect type, review recent plan
/aipeerreview -t security auth.ts      # Security review of auth.ts
/aipeerreview --type performance       # Performance review of recent plan
/aipeerreview setup.sh                 # General review of setup.sh
```

## Model Selection Rationale

Models chosen based on benchmark performance:

- **Claude Opus 4.5** - Best SWE-bench (80.9%), complex reasoning, agentic coding
- **GPT-5.1-Codex-Max** - Code-specialized, autonomous coding (77.9% SWE-bench)
- **Gemini 3 Pro** - Graduate-level reasoning (91.9% GPQA), academic knowledge
- **Claude Sonnet 4.5** - Balanced speed/capability (77.2% SWE-bench)
- **GPT-5.1** - Visual reasoning (85.4% MMMU), general purpose
- **GPT-5.1-Codex** - Code optimization, performance tuning

## Output Format

Each model provides:
1. **Summary** - One paragraph overview
2. **Strengths** - What's done well (3-5 points)
3. **Issues Found** - Problems ranked by severity
4. **Recommendations** - Specific, actionable improvements
5. **Questions** - Clarifications needed from author
