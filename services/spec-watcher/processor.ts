#!/usr/bin/env bun
/**
 * Spec Processor
 * Reads a spec file, creates an implementation plan, and gets AI peer review
 *
 * Usage: bun run processor.ts <spec-file> <output-plan-file>
 */

import { readFileSync, writeFileSync, existsSync } from "fs";
import { spawnSync } from "child_process";
import { basename, dirname } from "path";

// Parse YAML frontmatter from markdown
function parseFrontmatter(content: string): { frontmatter: Record<string, string>; body: string } {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) {
    return { frontmatter: {}, body: content };
  }

  const frontmatter: Record<string, string> = {};
  match[1].split("\n").forEach((line) => {
    const colonIdx = line.indexOf(":");
    if (colonIdx > 0) {
      const key = line.slice(0, colonIdx).trim();
      const value = line.slice(colonIdx + 1).trim();
      frontmatter[key] = value;
    }
  });

  return { frontmatter, body: match[2] };
}

// Call AI for peer review (legacy local fallback - prefer tkn-aipeerreview MCP server)
async function getAIPeerReview(plan: string): Promise<string> {
  const prompt = `Review this implementation plan critically. Focus on:
1. Missing steps or considerations
2. Potential bugs or edge cases
3. Security concerns
4. Performance implications
5. Better alternatives

Be concise but thorough. If the plan is solid, say so briefly.

PLAN:
${plan}`;

  // Try GitHub Copilot first (using spawn to avoid shell injection)
  try {
    const result = spawnSync("gh", ["copilot", "explain", prompt], {
      encoding: "utf-8",
      timeout: 90000,
      maxBuffer: 1024 * 1024,
    });
    if (result.status === 0 && result.stdout?.trim()) {
      return result.stdout.trim();
    }
  } catch {
    // Copilot not available
  }

  // Try Gemini CLI (using spawn with stdin to avoid shell injection)
  try {
    const result = spawnSync("gemini", ["-p", "Review this implementation plan critically"], {
      input: prompt,
      encoding: "utf-8",
      timeout: 90000,
      maxBuffer: 1024 * 1024,
    });
    if (result.status === 0 && result.stdout?.trim()) {
      return result.stdout.trim();
    }
  } catch {
    // Gemini not available
  }

  // No AI available - return placeholder
  return "_AI peer review not available locally. Use tkn-aipeerreview MCP server for multi-model review._";
}

// Generate implementation plan from spec
function generateImplementationPlan(spec: { frontmatter: Record<string, string>; body: string }): string {
  const { frontmatter, body } = spec;

  // Extract sections from spec body
  const sections: Record<string, string> = {};
  let currentSection = "intro";
  let currentContent: string[] = [];

  body.split("\n").forEach((line) => {
    if (line.startsWith("## ")) {
      if (currentContent.length > 0) {
        sections[currentSection] = currentContent.join("\n").trim();
      }
      currentSection = line.slice(3).trim().toLowerCase();
      currentContent = [];
    } else {
      currentContent.push(line);
    }
  });
  sections[currentSection] = currentContent.join("\n").trim();

  // Build implementation plan
  const plan = `# Implementation Plan

## Spec Summary

**Title:** ${frontmatter.title || "Untitled"}
**From:** ${frontmatter.from || "unknown"}
**Priority:** ${frontmatter.priority || "normal"}
**Project:** ${frontmatter.project || "current"}

${sections.summary || sections.intro || "No summary provided."}

## Requirements Analysis

${sections.requirements || "No requirements specified."}

## Implementation Steps

Based on the spec, here is the detailed implementation plan:

### Phase 1: Setup & Preparation
1. Review existing codebase for related functionality
2. Identify files that need modification
3. Create feature branch if using git

### Phase 2: Core Implementation
${generateStepsFromRequirements(sections.requirements || "")}

### Phase 3: Testing
1. Write unit tests for new functionality
2. Write integration tests if applicable
3. Manual testing against acceptance criteria

### Phase 4: Documentation & Cleanup
1. Update relevant documentation
2. Add inline code comments where needed
3. Clean up any temporary code

## Acceptance Criteria

${sections["acceptance criteria"] || "No acceptance criteria specified."}

## Files Likely to Change

_To be determined after codebase analysis._

## Estimated Complexity

${estimateComplexity(body)}

## Risk Assessment

${identifyRisks(body)}

---
*Plan generated: ${new Date().toISOString()}*
`;

  return plan;
}

function generateStepsFromRequirements(requirements: string): string {
  const lines = requirements.split("\n").filter((l) => l.trim().startsWith("-") || l.trim().startsWith("*"));

  if (lines.length === 0) {
    return "1. Implement core functionality as described in spec\n2. Handle edge cases\n3. Add error handling";
  }

  return lines
    .map((line, i) => {
      const req = line.replace(/^[\s\-\*]+/, "").trim();
      return `${i + 1}. Implement: ${req}`;
    })
    .join("\n");
}

function estimateComplexity(body: string): string {
  const wordCount = body.split(/\s+/).length;
  const requirementCount = (body.match(/^[\s]*[-*]/gm) || []).length;

  if (wordCount < 200 && requirementCount < 5) {
    return "**Low** - Small, focused change";
  } else if (wordCount < 500 && requirementCount < 10) {
    return "**Medium** - Moderate scope, may touch multiple files";
  } else {
    return "**High** - Large scope, consider breaking into smaller specs";
  }
}

function identifyRisks(body: string): string {
  const risks: string[] = [];
  const lowerBody = body.toLowerCase();

  if (lowerBody.includes("database") || lowerBody.includes("migration")) {
    risks.push("- Database changes may require migration strategy");
  }
  if (lowerBody.includes("api") || lowerBody.includes("endpoint")) {
    risks.push("- API changes may affect existing clients");
  }
  if (lowerBody.includes("auth") || lowerBody.includes("security") || lowerBody.includes("password")) {
    risks.push("- Security-sensitive changes require careful review");
  }
  if (lowerBody.includes("performance") || lowerBody.includes("optimize")) {
    risks.push("- Performance changes should be benchmarked");
  }
  if (lowerBody.includes("breaking") || lowerBody.includes("deprecat")) {
    risks.push("- Breaking changes require version bump and changelog");
  }

  return risks.length > 0 ? risks.join("\n") : "- No significant risks identified";
}

// Main
async function main() {
  const [specFile, outputFile] = process.argv.slice(2);

  if (!specFile || !outputFile) {
    console.error("Usage: bun run processor.ts <spec-file> <output-plan-file>");
    process.exit(1);
  }

  if (!existsSync(specFile)) {
    console.error(`Spec file not found: ${specFile}`);
    process.exit(1);
  }

  console.log(`Processing spec: ${specFile}`);

  // Read and parse spec
  const specContent = readFileSync(specFile, "utf-8");
  const spec = parseFrontmatter(specContent);

  // Generate implementation plan
  console.log("Generating implementation plan...");
  let plan = generateImplementationPlan(spec);

  // Get AI peer review
  console.log("Getting AI peer review...");
  const review = await getAIPeerReview(plan);

  // Append review to plan
  plan += `\n## AI Peer Review\n\n${review}\n`;

  // Add approval section
  plan += `
---

## Approval Required

This plan has been auto-generated and AI peer-reviewed.
**Implementation requires user approval.**

To approve and start implementation:
\`\`\`
/approve-spec ${basename(outputFile)}
\`\`\`

To reject or request changes:
\`\`\`
/reject-spec ${basename(outputFile)} "reason"
\`\`\`

---
*Original spec: ${specFile}*
`;

  // Write plan
  writeFileSync(outputFile, plan);
  console.log(`Plan written to: ${outputFile}`);
}

main().catch((err) => {
  console.error("Error:", err);
  process.exit(1);
});
