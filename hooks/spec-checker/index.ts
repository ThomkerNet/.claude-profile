#!/usr/bin/env bun
/**
 * Per-Session Spec Checker Hook
 *
 * Runs on each user prompt submission to check for pending *-SPEC.md files
 * in the current project's .claude-specs/ directory.
 *
 * When idle for 5+ minutes and new specs exist, injects context prompting
 * Claude to offer spec processing to the user.
 *
 * This is a per-project hook - only checks the current working directory.
 */

import { existsSync, readdirSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join, dirname } from "path";
import { homedir } from "os";

interface HookInput {
  cwd?: string;
  workspace?: { current_dir: string };
  session_id?: string;
  hook_event_name?: string;
  user_prompt?: string;
}

interface ActivityState {
  lastActivity: number;
  lastSpecCheck: number;
  notifiedSpecs: string[];  // MD5 hashes of specs we've already notified about
}

interface SpecInfo {
  path: string;
  name: string;
  title: string;
  from: string;
  priority: string;
  hash: string;
}

const CLAUDE_HOME = join(homedir(), ".claude");
const ACTIVITY_FILE = join(CLAUDE_HOME, ".spec-checker-activity.json");
const SPEC_REGISTRY = join(CLAUDE_HOME, ".spec-registry.json");
const IDLE_THRESHOLD_MS = 5 * 60 * 1000; // 5 minutes
const CHECK_COOLDOWN_MS = 60 * 1000; // Don't check more than once per minute

/**
 * Simple MD5 hash (for deduplication, not security)
 */
function simpleHash(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).padStart(8, '0');
}

/**
 * Read activity state
 */
function readActivityState(): ActivityState {
  try {
    if (existsSync(ACTIVITY_FILE)) {
      return JSON.parse(readFileSync(ACTIVITY_FILE, "utf-8"));
    }
  } catch {
    // Ignore errors
  }
  return {
    lastActivity: Date.now(),
    lastSpecCheck: 0,
    notifiedSpecs: []
  };
}

/**
 * Write activity state
 */
function writeActivityState(state: ActivityState): void {
  try {
    mkdirSync(dirname(ACTIVITY_FILE), { recursive: true });
    writeFileSync(ACTIVITY_FILE, JSON.stringify(state, null, 2));
  } catch {
    // Ignore errors
  }
}

/**
 * Check if a spec has been processed (has a plan)
 */
function isSpecProcessed(specPath: string): boolean {
  if (!existsSync(SPEC_REGISTRY)) return false;

  try {
    const content = readFileSync(specPath, "utf-8");
    const hash = simpleHash(content);
    const registry = JSON.parse(readFileSync(SPEC_REGISTRY, "utf-8"));
    return registry.specs?.some((s: any) =>
      s.hash === hash && (s.status === "planned" || s.status === "approved" || s.status === "completed")
    ) ?? false;
  } catch {
    return false;
  }
}

/**
 * Parse YAML frontmatter from spec file
 */
function parseSpecFrontmatter(content: string): Record<string, string> {
  const frontmatter: Record<string, string> = {};
  const match = content.match(/^---\n([\s\S]*?)\n---/);

  if (match) {
    const yaml = match[1];
    for (const line of yaml.split("\n")) {
      const colonIdx = line.indexOf(":");
      if (colonIdx > 0) {
        const key = line.slice(0, colonIdx).trim();
        const value = line.slice(colonIdx + 1).trim();
        frontmatter[key] = value;
      }
    }
  }

  return frontmatter;
}

/**
 * Find new specs in the current project
 */
function findNewSpecs(projectDir: string, notifiedHashes: string[]): SpecInfo[] {
  const specDir = join(projectDir, ".claude-specs");
  const newSpecs: SpecInfo[] = [];

  if (!existsSync(specDir)) {
    return newSpecs;
  }

  try {
    const files = readdirSync(specDir);

    for (const file of files) {
      if (!file.match(/-SPEC\.(md|MD)$/i)) continue;

      const specPath = join(specDir, file);
      const content = readFileSync(specPath, "utf-8");
      const hash = simpleHash(content);

      // Skip if already notified or processed
      if (notifiedHashes.includes(hash)) continue;
      if (isSpecProcessed(specPath)) continue;

      const frontmatter = parseSpecFrontmatter(content);

      newSpecs.push({
        path: specPath,
        name: file,
        title: frontmatter.title || file.replace(/-SPEC\.(md|MD)$/i, ""),
        from: frontmatter.from || "unknown",
        priority: frontmatter.priority || "medium",
        hash
      });
    }
  } catch {
    // Ignore errors
  }

  return newSpecs;
}

async function main() {
  const input = await Bun.stdin.text();

  if (!input) {
    process.exit(0);
  }

  try {
    const hookData: HookInput = JSON.parse(input);
    const cwd = hookData.cwd || hookData.workspace?.current_dir || process.cwd();
    const now = Date.now();

    // Read current state
    const state = readActivityState();
    const idleTime = now - state.lastActivity;
    const timeSinceLastCheck = now - state.lastSpecCheck;

    // Update activity timestamp
    state.lastActivity = now;

    // Check cooldown
    if (timeSinceLastCheck < CHECK_COOLDOWN_MS) {
      writeActivityState(state);
      process.exit(0);
    }

    // Find new specs
    const newSpecs = findNewSpecs(cwd, state.notifiedSpecs);

    if (newSpecs.length === 0) {
      writeActivityState(state);
      process.exit(0);
    }

    // Only notify if idle for 5+ minutes OR if high priority specs exist
    const hasHighPriority = newSpecs.some(s => s.priority === "high");

    if (idleTime < IDLE_THRESHOLD_MS && !hasHighPriority) {
      writeActivityState(state);
      process.exit(0);
    }

    // Update state with notified specs
    state.notifiedSpecs.push(...newSpecs.map(s => s.hash));
    state.lastSpecCheck = now;
    writeActivityState(state);

    // Build notification message
    const specList = newSpecs.map(s =>
      `- **${s.title}** (from: ${s.from}, priority: ${s.priority})\n  File: \`${s.name}\``
    ).join("\n");

    const idleMinutes = Math.floor(idleTime / 60000);
    const idleNote = idleTime >= IDLE_THRESHOLD_MS
      ? `\n\n*Detected after ${idleMinutes} minutes of idle time.*`
      : "";

    const context = `<spec-notification>
## 📋 New Spec${newSpecs.length > 1 ? "s" : ""} Detected

${newSpecs.length} new specification file${newSpecs.length > 1 ? "s" : ""} found in this project:

${specList}${idleNote}

**Suggested action:** Ask the user if they would like you to review and create an implementation plan for ${newSpecs.length > 1 ? "these specs" : "this spec"}.

Use \`/review-spec\` to show the spec details, or read the file directly and offer to create a detailed implementation plan with AI peer review.
</spec-notification>`;

    console.log(JSON.stringify({
      hookSpecificOutput: {
        additionalContext: context
      }
    }));

  } catch (error) {
    // Silent failure - don't disrupt user's workflow
    process.exit(0);
  }
}

main();
