# AI Peer Review Command

> **Description:** Smart multi-model code review via LiteLLM proxy

**Invoke:** /Users/sbarker/.bun/bin/bun run /Users/sbarker/.claude/scripts/aipeerreview/index.ts

## Usage

```
/aipeerreview [options] [file]
```

## Options

- `-t, --type <type>` - Review type (auto-detected if omitted)
- `-m, --mode <mode>` - File selection: git (default), plan
- `-h, --help` - Show help

## Review Types & Model Selection

| Type | Models | Best For |
|------|--------|----------|
| **security** | GPT-5.1, Gemini 3 Pro, DeepSeek R1 | Auth, injection, OWASP vulnerabilities |
| **architecture** | Gemini 3 Pro, GPT-5.1, Gemini 2.5 Pro | Design patterns, scalability, coupling |
| **bug** | GPT-5.1, DeepSeek R1, Gemini 2.5 Pro | Logic errors, edge cases, race conditions |
| **performance** | GPT-5, Gemini 3 Pro, DeepSeek R1 | Complexity, optimization, bottlenecks |
| **api** | GPT-5.1, Gemini 3 Pro, Gemini 2.5 Pro | REST design, contracts, versioning |
| **test** | GPT-5.1, Gemini 2.5 Pro, DeepSeek R1 | Coverage gaps, mocking, assertions |
| **general** | GPT-5.1, Gemini 3 Pro, Gemini 2.5 Pro | Broad code quality assessment |

## Examples

```bash
/aipeerreview                          # Auto-detect type, review git changes
/aipeerreview -t security auth.ts      # Security review of auth.ts
/aipeerreview --mode plan              # Review most recent plan
/aipeerreview setup.sh                 # General review of setup.sh
```

## Backend

Uses direct HTTP calls to **LiteLLM proxy** for multi-model access:

- Proxy: `http://100.74.34.7:4000/v1` (homelab LiteLLM)
- No external CLI dependencies - just bun + fetch

## Available Models

| Model | Use Case |
|-------|----------|
| GPT-5.1 | General, visual reasoning, security |
| GPT-5 | Coding, reasoning, performance |
| GPT-5 Mini | Fast, cost-effective |
| Gemini 3 Pro | Academic, architecture, complex reasoning |
| Gemini 2.5 Pro | Reasoning, code analysis |
| Gemini 2.5 Flash | Fast tasks |
| DeepSeek R1 | Logic, bug detection, local |

> **Note:** Claude models are accessed directly via Claude Code, not through this proxy.

## Output Format

Each model provides:
1. **Summary** - One paragraph overview
2. **Strengths** - What's done well (3-5 points)
3. **Issues Found** - Problems ranked by severity
4. **Recommendations** - Specific, actionable improvements
5. **Questions** - Clarifications needed from author
