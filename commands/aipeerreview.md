# AI Peer Review Command

> **Description:** Smart multi-model code review via LiteLLM proxy

**Invoke:** bun run ~/.claude/scripts/aipeerreview/index.ts

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
| **security** | GPT-5.1, Gemini 3 Pro, Gemini 2.5 Pro | Auth, injection, OWASP vulnerabilities |
| **architecture** | GPT-5.2, Gemini 3 Pro, Gemini 2.5 Pro | Design patterns, scalability, coupling |
| **bug** | GPT-5.2, Gemini 3 Pro, Gemini 2.5 Pro | Logic errors, edge cases, race conditions |
| **performance** | GPT-5.2, Gemini 3 Pro, Gemini 2.5 Pro | Complexity, optimization, bottlenecks |
| **api** | GPT-5.1, Gemini 3 Pro, Gemini 2.5 Pro | REST design, contracts, versioning |
| **test** | GPT-5.1 Codex, Gemini 2.5 Pro, Gemini 3 Flash | Coverage gaps, mocking, assertions |
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

| Model | Provider | Use Case |
|-------|----------|----------|
| GPT-5.2 | OpenAI (Copilot) | Complex analysis, debugging, architecture |
| GPT-5.1 | OpenAI (Copilot) | General, visual reasoning, security, API design |
| GPT-5.1 Codex | OpenAI (Copilot) | Code engineering, refactoring, test coverage |
| Gemini 3 Pro | Google API | Long-context reasoning, architecture |
| Gemini 3 Flash | Google API | Fast reviews, repetitive checks |
| Gemini 2.5 Pro | Google API | Code analysis, bug detection |

> **Note:** Claude models are accessed directly via Claude Code, not through LiteLLM. Gemini models route through Google API to reduce Copilot usage.

## Output Format

Each model provides:
1. **Summary** - One paragraph overview
2. **Strengths** - What's done well (3-5 points)
3. **Issues Found** - Problems ranked by severity
4. **Recommendations** - Specific, actionable improvements
5. **Questions** - Clarifications needed from author
