#!/usr/bin/env bun
/**
 * Plan Peer Review Hook (PostToolUse → ExitPlanMode)
 *
 * After a plan is finalized via ExitPlanMode, injects context instructing
 * Claude to submit the plan for AI multi-model peer review and action
 * any HIGH or CRITICAL consensus findings before presenting to the user.
 */

interface HookInput {
  session_id: string;
  cwd: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
  tool_response: string;
}

async function main() {
  const input = await Bun.stdin.text();
  if (!input) process.exit(0);

  try {
    const hookData: HookInput = JSON.parse(input);

    const context = `<plan-peer-review-required>
**Automatic Peer Review Triggered — Do NOT present the plan to the user yet.**

A plan has just been finalized. Before the user sees it, you MUST run a peer review:

**Step 1 — Collect the plan**
Gather the full plan content you just wrote. It should be in your recent context or in the plan file.

**Step 2 — Submit for peer review**
Use \`mcp__tkn-aipeerreview__peer_review\`:
- \`content\`: The full plan text
- \`review_type\`: null (let the server auto-detect)
- \`models\`: null (use default multi-model ensemble)

**Step 3 — Triage findings by severity**

| Severity | Action |
|----------|--------|
| **CRITICAL** | MUST fix in the plan before presenting. Update the plan file. |
| **HIGH** | MUST fix in the plan before presenting. Update the plan file. |
| **MEDIUM** | Add as "Peer Review Notes" section at the end of the plan. Do not block. |
| **LOW** | Ignore. |

**Step 4 — Re-present the plan**
- If you updated the plan, call ExitPlanMode again with the revised version.
- If no HIGH/CRITICAL findings, proceed normally — optionally note that peer review passed clean.
- Include a brief summary of what the peer review found (if anything).

**Loop guard:** If you have already peer-reviewed this plan in this conversation turn (check for prior \`<plan-peer-review-required>\` and peer_review tool results in context), do NOT review again. Proceed with ExitPlanMode normally.
</plan-peer-review-required>`;

    console.log(
      JSON.stringify({
        hookSpecificOutput: {
          additionalContext: context,
        },
      })
    );
  } catch (error) {
    console.error("Plan peer review hook error:", error);
    process.exit(0);
  }
}

main();
