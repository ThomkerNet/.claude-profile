# AI Peer Review Command

> **Description:** Run peer reviews of recent plans or issues using multiple AI models (ChatGPT, Gemini, Claude)

**Invoke:** /Users/sbarker/.bun/bin/bun run /Users/sbarker/.claude/scripts/aipeerreview/index.ts

## Usage

```
/aipeerreview [file]
```

## Options

- **file** (optional): Path to the plan/issue file to review. If omitted, uses the most recent plan or issue.

## Examples

```
/aipeerreview                                    # Review most recent plan
/aipeerreview plans/my-feature.md               # Review specific plan
```

## What It Does

1. Finds the most recent plan or issue if no file specified
2. Sends the content to multiple AI models for review via Copilot CLI:
   - **ChatGPT** (gpt-5.1) - Primary review
   - **Gemini** (gemini-3-pro-preview) - Alternative perspective
   - **Claude** (claude-opus-4.5) - Additional validation

3. Aggregates feedback and insights from all models
4. Highlights consensus areas and divergent opinions

## Models Used

The command automatically invokes peer review across:
- `gpt-5.1` - ChatGPT's latest reasoning model
- `gemini-3-pro-preview` - Google's latest Gemini Pro
- `claude-opus-4.5` - Anthropic's Opus model for validation

## Output

Each model provides:
- Strengths and weaknesses
- Potential issues or improvements
- Architectural concerns
- Security/performance notes
- Feasibility assessment
