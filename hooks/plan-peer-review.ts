#!/usr/bin/env bun
/**
 * Plan Peer Review Hook (PostToolUse → ExitPlanMode)
 *
 * After a plan is finalized via ExitPlanMode, injects context instructing
 * Claude to submit the plan for AI multi-model peer review and action
 * any HIGH or CRITICAL consensus findings before presenting to the user.
 *
 * Security: Validates tool_name, uses file-based stateful loop guard
 * keyed by session_id to prevent infinite review cycles.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

const GUARD_DIR = join(tmpdir(), "claude-hook-guards");
const GUARD_TTL_MS = 10 * 60 * 1000; // 10 minutes

// --- Input Validation (HIGH fix) ---

function validateHookInput(
  data: unknown
): { session_id: string; tool_name: string } | null {
  if (!data || typeof data !== "object") return null;
  const d = data as Record<string, unknown>;

  if (typeof d.session_id !== "string" || !d.session_id) return null;
  if (typeof d.tool_name !== "string" || !d.tool_name) return null;

  return { session_id: d.session_id, tool_name: d.tool_name };
}

// --- Stateful Loop Guard (CRITICAL fix) ---

function getGuardPath(sessionId: string): string {
  // Sanitize session ID for use as filename
  const safeId = sessionId.replace(/[^a-zA-Z0-9_-]/g, "_");
  return join(GUARD_DIR, `plan-review-${safeId}`);
}

function hasRecentReview(sessionId: string): boolean {
  const guardPath = getGuardPath(sessionId);
  if (!existsSync(guardPath)) return false;

  try {
    const content = readFileSync(guardPath, "utf-8").trim();
    const timestamp = parseInt(content, 10);
    if (isNaN(timestamp)) return false;
    return Date.now() - timestamp < GUARD_TTL_MS;
  } catch {
    return false;
  }
}

function markReviewed(sessionId: string): void {
  try {
    if (!existsSync(GUARD_DIR)) {
      mkdirSync(GUARD_DIR, { recursive: true });
    }
    writeFileSync(getGuardPath(sessionId), String(Date.now()));
  } catch {
    // Non-fatal: worst case we review again
  }
}

// --- Main ---

async function main() {
  const input = (await Bun.stdin.text()).trim();
  if (!input) process.exit(0);

  try {
    const parsed = JSON.parse(input);
    const hookData = validateHookInput(parsed);

    if (!hookData) {
      console.error("Plan peer review hook: invalid hook payload shape");
      process.exit(0);
    }

    // CRITICAL fix: verify this is actually ExitPlanMode
    if (hookData.tool_name !== "ExitPlanMode") {
      process.exit(0);
    }

    // CRITICAL fix: stateful loop guard — skip if already reviewed this session
    if (hasRecentReview(hookData.session_id)) {
      process.exit(0);
    }

    // Mark as reviewed BEFORE injecting (prevents re-entry)
    markReviewed(hookData.session_id);

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
