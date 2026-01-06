#!/usr/bin/env bun
/**
 * Preference Detector Hook (UserPromptSubmit)
 *
 * Detects when user expresses preferences or corrections in their messages.
 * Adds a hint to Claude to consider storing these in memory.
 *
 * Signals detected:
 * - "I prefer X" / "I always use X" / "I never use X"
 * - "No, use X instead" / "Actually, X not Y"
 * - "We use X in this project" / "This project uses X"
 * - "Don't do X" / "Always do X"
 * - "Remember that X" / "Note that X"
 */

interface PreferenceMatch {
  type: "preference" | "correction" | "project_pattern" | "instruction";
  signal: string;
  excerpt: string;
}

const PREFERENCE_PATTERNS: { pattern: RegExp; type: PreferenceMatch["type"] }[] = [
  // Direct preferences
  { pattern: /\bi\s+(prefer|like|want|always use|never use|always|never)\b/i, type: "preference" },
  { pattern: /\bdon'?t\s+(use|do|add|include|want)\b/i, type: "preference" },
  { pattern: /\bplease\s+(always|never|don'?t)\b/i, type: "instruction" },

  // Corrections
  { pattern: /\bno,?\s+(use|it'?s|we use|actually)\b/i, type: "correction" },
  { pattern: /\bactually,?\s+(we|it|use|it'?s)\b/i, type: "correction" },
  { pattern: /\binstead\s+of\b/i, type: "correction" },
  { pattern: /\bnot\s+\w+,?\s+(but|use)\b/i, type: "correction" },

  // Project patterns
  { pattern: /\b(we|this project|our team)\s+(use|uses|always|never)\b/i, type: "project_pattern" },
  { pattern: /\b(in this (project|repo|codebase))\b/i, type: "project_pattern" },
  { pattern: /\bour\s+(convention|pattern|style|standard)\b/i, type: "project_pattern" },

  // Explicit memory instructions
  { pattern: /\bremember\s+(that|this|to)\b/i, type: "instruction" },
  { pattern: /\bnote\s+(that|this)\b/i, type: "instruction" },
  { pattern: /\bkeep in mind\b/i, type: "instruction" },
  { pattern: /\bfor (future|next time)\b/i, type: "instruction" },
];

function detectPreferences(message: string): PreferenceMatch[] {
  const matches: PreferenceMatch[] = [];

  for (const { pattern, type } of PREFERENCE_PATTERNS) {
    const match = message.match(pattern);
    if (match) {
      // Extract surrounding context (50 chars before/after)
      const idx = match.index || 0;
      const start = Math.max(0, idx - 30);
      const end = Math.min(message.length, idx + match[0].length + 50);
      const excerpt = message.slice(start, end).trim();

      matches.push({
        type,
        signal: match[0],
        excerpt: excerpt.length > 80 ? excerpt.slice(0, 80) + "..." : excerpt
      });
    }
  }

  // Deduplicate by type
  const seen = new Set<string>();
  return matches.filter(m => {
    const key = m.type;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function formatHint(matches: PreferenceMatch[]): string {
  const hints: string[] = [];

  const corrections = matches.filter(m => m.type === "correction");
  const preferences = matches.filter(m => m.type === "preference");
  const patterns = matches.filter(m => m.type === "project_pattern");
  const instructions = matches.filter(m => m.type === "instruction");

  if (corrections.length > 0) {
    hints.push("User is correcting something - store the correction in memory to avoid repeating the mistake.");
  }
  if (preferences.length > 0) {
    hints.push("User expressed a preference - consider storing in memory (user entity).");
  }
  if (patterns.length > 0) {
    hints.push("User mentioned a project convention - consider storing in memory (project entity).");
  }
  if (instructions.length > 0) {
    hints.push("User wants you to remember something - store in memory.");
  }

  return hints.join("\n");
}

async function main() {
  const input = await Bun.stdin.text();

  if (!input) {
    process.exit(0);
  }

  try {
    const hookData = JSON.parse(input);
    const message = hookData.user_prompt_submit_data?.prompt || "";

    if (!message || message.length < 10) {
      process.exit(0);
    }

    const matches = detectPreferences(message);

    if (matches.length === 0) {
      process.exit(0);
    }

    const hint = formatHint(matches);

    const context = `<preference-detected>
**Memory Hint:** ${hint}

Detected signals: ${matches.map(m => `"${m.signal}"`).join(", ")}

If this is a reusable preference/pattern, store it:
\`\`\`javascript
// For user preference:
add_observations([{entityName: "user", contents: ["<preference>"]}])

// For project pattern:
add_observations([{entityName: "<project>", contents: ["<pattern>"]}])
\`\`\`
</preference-detected>`;

    console.log(JSON.stringify({
      hookSpecificOutput: {
        additionalContext: context
      }
    }));

  } catch (error) {
    console.error("Preference detector error:", error);
    process.exit(0);
  }
}

main();
