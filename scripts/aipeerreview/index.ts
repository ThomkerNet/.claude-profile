#!/usr/bin/env bun
/**
 * AI Peer Review - Multi-model code/plan review via Copilot CLI
 * Reviews content using the 3 most appropriate AI models based on review type
 *
 * Model selection based on benchmark performance:
 * - Claude Opus 4.5: Best SWE-bench (80.9%), complex reasoning, agentic coding
 * - GPT-5.1-Codex-Max: Strong code (77.9%), terminal coding (58.1%)
 * - Gemini 3 Pro: Best academic reasoning (91.9% GPQA), multilingual
 * - Claude Sonnet 4.5: Balanced (77.2% SWE-bench), fast, cost-effective
 * - GPT-5.1: Visual reasoning (85.4% MMMU), general reasoning
 */

import { readFileSync, readdirSync, statSync, writeFileSync, mkdtempSync, rmSync } from "fs";
import { resolve, basename, join } from "path";
import { exec } from "child_process";
import { promisify } from "util";
import { tmpdir } from "os";

const execAsync = promisify(exec);

// All available models with their characteristics
const ALL_MODELS = {
  "claude-opus-4.5": {
    name: "Claude Opus 4.5",
    description: "Best for complex reasoning, agentic coding, multi-system bugs (80.9% SWE-bench)",
    strengths: ["complex-reasoning", "agentic", "tool-use", "ambiguity", "security"],
  },
  "gpt-5.1-codex-max": {
    name: "GPT-5.1 Codex Max",
    description: "Code-specialized, autonomous coding, terminal proficiency (77.9% SWE-bench)",
    strengths: ["code-patterns", "terminal", "autonomous", "refactoring"],
  },
  "gemini-3-pro-preview": {
    name: "Gemini 3 Pro",
    description: "Graduate-level reasoning, academic knowledge, multilingual (91.9% GPQA)",
    strengths: ["academic", "architecture", "security-theory", "multilingual"],
  },
  "claude-sonnet-4.5": {
    name: "Claude Sonnet 4.5",
    description: "Balanced speed/capability, strong tool use (77.2% SWE-bench)",
    strengths: ["balanced", "fast", "tool-use", "practical"],
  },
  "gpt-5.1": {
    name: "GPT-5.1",
    description: "Visual reasoning, general purpose, adaptive (85.4% MMMU)",
    strengths: ["visual", "general", "api-design", "documentation"],
  },
  "gpt-5.1-codex": {
    name: "GPT-5.1 Codex",
    description: "Code optimization, performance tuning",
    strengths: ["optimization", "performance", "algorithms"],
  },
} as const;

type ModelId = keyof typeof ALL_MODELS;

// Review types with optimal model selection (3 models each)
const REVIEW_TYPE_MODELS: Record<string, { models: ModelId[]; focusAreas: string[] }> = {
  security: {
    models: ["claude-opus-4.5", "gpt-5.1-codex-max", "gemini-3-pro-preview"],
    focusAreas: [
      "Injection vulnerabilities (SQL, XSS, command injection)",
      "Authentication and authorization flaws",
      "Data exposure and sensitive information leaks",
      "Input validation and sanitization",
      "Cryptographic issues and secure storage",
      "OWASP Top 10 vulnerabilities",
    ],
  },
  architecture: {
    models: ["claude-opus-4.5", "gemini-3-pro-preview", "claude-sonnet-4.5"],
    focusAreas: [
      "Design patterns and anti-patterns",
      "Scalability and maintainability",
      "Separation of concerns",
      "Dependency management",
      "System boundaries and interfaces",
      "Technical debt and coupling",
    ],
  },
  bug: {
    models: ["claude-opus-4.5", "gpt-5.1-codex-max", "claude-sonnet-4.5"],
    focusAreas: [
      "Logic errors and edge cases",
      "Race conditions and concurrency issues",
      "Null/undefined handling",
      "Error handling completeness",
      "Off-by-one errors and boundary conditions",
      "Resource leaks and cleanup",
    ],
  },
  performance: {
    models: ["claude-opus-4.5", "gpt-5.1-codex", "gemini-3-pro-preview"],
    focusAreas: [
      "Algorithm complexity (time/space)",
      "Database query optimization",
      "Memory usage and allocation",
      "Network and I/O efficiency",
      "Caching opportunities",
      "Bottleneck identification",
    ],
  },
  api: {
    models: ["claude-opus-4.5", "gpt-5.1", "claude-sonnet-4.5"],
    focusAreas: [
      "API design and RESTful principles",
      "Contract clarity and documentation",
      "Error response consistency",
      "Versioning strategy",
      "Rate limiting and pagination",
      "Backward compatibility",
    ],
  },
  test: {
    models: ["claude-opus-4.5", "gpt-5.1-codex-max", "claude-sonnet-4.5"],
    focusAreas: [
      "Test coverage gaps",
      "Edge case coverage",
      "Mock and stub quality",
      "Test isolation and independence",
      "Assertion quality",
      "Integration test completeness",
    ],
  },
  general: {
    models: ["claude-opus-4.5", "gpt-5.1", "gemini-3-pro-preview"],
    focusAreas: [
      "Code architecture and design",
      "Security implications",
      "Feasibility and implementation concerns",
      "Best practices alignment",
      "Potential pitfalls and edge cases",
      "Suggestions for improvement",
    ],
  },
};

type ReviewType = keyof typeof REVIEW_TYPE_MODELS;

// Auto-detect review type from content
function detectReviewType(content: string): ReviewType {
  const contentLower = content.toLowerCase();

  const typePatterns: Array<{ type: ReviewType; patterns: string[]; weight: number }> = [
    {
      type: "security",
      patterns: ["security", "auth", "vulnerability", "injection", "xss", "csrf", "permission", "credential", "encrypt", "token", "oauth", "jwt"],
      weight: 0,
    },
    {
      type: "architecture",
      patterns: ["architecture", "design", "pattern", "structure", "scalab", "microservice", "monolith", "component", "module", "layer", "dependency"],
      weight: 0,
    },
    {
      type: "bug",
      patterns: ["bug", "fix", "error", "exception", "crash", "issue", "broken", "failing", "null", "undefined", "race condition"],
      weight: 0,
    },
    {
      type: "performance",
      patterns: ["performance", "optim", "slow", "fast", "memory", "cache", "latency", "throughput", "bottleneck", "efficient", "complexity"],
      weight: 0,
    },
    {
      type: "api",
      patterns: ["api", "endpoint", "rest", "graphql", "request", "response", "route", "handler", "middleware", "contract"],
      weight: 0,
    },
    {
      type: "test",
      patterns: ["test", "spec", "coverage", "mock", "stub", "assert", "expect", "jest", "vitest", "pytest", "unit test", "integration"],
      weight: 0,
    },
  ];

  // Count pattern matches
  for (const tp of typePatterns) {
    for (const pattern of tp.patterns) {
      const regex = new RegExp(pattern, "gi");
      const matches = contentLower.match(regex);
      tp.weight += matches ? matches.length : 0;
    }
  }

  // Sort by weight and get top match
  typePatterns.sort((a, b) => b.weight - a.weight);

  // Only use detected type if weight is significant (>2 matches)
  if (typePatterns[0].weight > 2) {
    return typePatterns[0].type;
  }

  return "general";
}

function findMostRecentPlan(filePath?: string): string {
  if (filePath) {
    const fullPath = resolve(filePath);
    try {
      statSync(fullPath);
      return fullPath;
    } catch {
      console.error(`File not found: ${filePath}`);
      process.exit(1);
    }
  }

  const plansDir = resolve(process.env.HOME || ".", ".claude", "plans");
  const queueFile = resolve(process.env.HOME || ".", ".claude", "queue.md");

  let files: string[] = [];

  try {
    const planFiles = readdirSync(plansDir)
      .filter((f) => f.endsWith(".md"))
      .map((f) => resolve(plansDir, f));
    files = [...files, ...planFiles];
  } catch {
    // Plans directory doesn't exist
  }

  try {
    statSync(queueFile);
    files.push(queueFile);
  } catch {
    // Queue file doesn't exist
  }

  if (files.length === 0) {
    console.error("No plans or issues found. Create a plan first or specify a file path.");
    process.exit(1);
  }

  const mostRecent = files.reduce((latest, current) => {
    const latestTime = statSync(latest).mtime.getTime();
    const currentTime = statSync(current).mtime.getTime();
    return currentTime > latestTime ? current : latest;
  });

  return mostRecent;
}

function readFileContent(filePath: string): string {
  try {
    return readFileSync(filePath, "utf-8");
  } catch (error) {
    console.error(`Failed to read file: ${filePath}`);
    process.exit(1);
  }
}

async function reviewWithModel(
  modelId: ModelId,
  content: string,
  reviewType: ReviewType
): Promise<{ model: string; result: string; error?: string }> {
  const model = ALL_MODELS[modelId];
  const config = REVIEW_TYPE_MODELS[reviewType];

  const focusAreasList = config.focusAreas.map((a) => `- ${a}`).join("\n");

  const reviewPrompt = `You are conducting a ${reviewType.toUpperCase()} peer review. Your expertise: ${model.description}

Focus on these specific areas:
${focusAreasList}

Document to review:
---
${content}
---

Provide a structured review with:
1. **Summary** - One paragraph overview
2. **Strengths** - What's done well (3-5 points)
3. **Issues Found** - Problems ranked by severity (Critical > High > Medium > Low)
4. **Recommendations** - Specific, actionable improvements
5. **Questions** - Clarifications needed from the author

Be concise but thorough. Prioritize actionable feedback over generic advice.`;

  let tmpDir: string | null = null;

  try {
    tmpDir = mkdtempSync(join(tmpdir(), "copilot-review-"));
    const promptFile = join(tmpDir, "prompt.txt");

    writeFileSync(promptFile, reviewPrompt, { mode: 0o600 });

    const cmd = `copilot --model ${modelId} --silent -p "$(cat ${promptFile})"`;
    const { stdout } = await execAsync(cmd, {
      encoding: "utf-8",
      maxBuffer: 10 * 1024 * 1024,
      timeout: 300000,
    });

    return { model: model.name, result: stdout, error: undefined };
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : "Unknown error occurred";
    return {
      model: model.name,
      result: "",
      error: `Failed to get review from ${model.name}: ${errorMsg}`,
    };
  } finally {
    if (tmpDir) {
      try {
        rmSync(tmpDir, { recursive: true, force: true });
      } catch {
        // Silently ignore cleanup errors
      }
    }
  }
}

function parseArgs(): { filePath?: string; reviewType?: ReviewType } {
  const args = process.argv.slice(2);
  let filePath: string | undefined;
  let reviewType: ReviewType | undefined;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === "--type" || arg === "-t") {
      const typeArg = args[++i]?.toLowerCase();
      if (typeArg && typeArg in REVIEW_TYPE_MODELS) {
        reviewType = typeArg as ReviewType;
      } else {
        console.error(`Invalid review type. Available: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}`);
        process.exit(1);
      }
    } else if (arg === "--help" || arg === "-h") {
      console.log(`
AI Peer Review - Smart multi-model code review

Usage: /aipeerreview [options] [file]

Options:
  -t, --type <type>  Review type: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}
  -h, --help         Show this help

Review Types & Models:
${Object.entries(REVIEW_TYPE_MODELS)
  .map(([type, config]) => `  ${type.padEnd(12)} → ${config.models.map((m) => ALL_MODELS[m].name).join(", ")}`)
  .join("\n")}

Examples:
  /aipeerreview                          # Auto-detect type, review recent plan
  /aipeerreview -t security auth.ts      # Security review of auth.ts
  /aipeerreview --type performance       # Performance review of recent plan
`);
      process.exit(0);
    } else if (!arg.startsWith("-")) {
      filePath = arg;
    }
  }

  return { filePath, reviewType };
}

async function main(): Promise<void> {
  const { filePath, reviewType: explicitType } = parseArgs();
  const documentPath = findMostRecentPlan(filePath);
  const fileName = basename(documentPath);
  const content = readFileContent(documentPath);

  // Detect or use explicit review type
  const reviewType = explicitType || detectReviewType(content);
  const config = REVIEW_TYPE_MODELS[reviewType];
  const models = config.models;

  const startTime = Date.now();

  console.log(`\n${"═".repeat(70)}`);
  console.log(`   AI PEER REVIEW - ${reviewType.toUpperCase()} Analysis`);
  console.log(`${"═".repeat(70)}\n`);
  console.log(`📄 Document: ${fileName}`);
  console.log(`🎯 Review Type: ${reviewType}${explicitType ? " (explicit)" : " (auto-detected)"}`);
  console.log(`🤖 Models: ${models.map((m) => ALL_MODELS[m].name).join(" → ")}`);
  console.log(`\n⚡ Starting parallel peer review across ${models.length} AI models...\n`);

  // Run reviews in parallel
  const reviews = await Promise.all(
    models.map((modelId) => reviewWithModel(modelId, content, reviewType))
  );

  // Display results
  for (const review of reviews) {
    console.log(`\n${"─".repeat(70)}`);
    console.log(`📋 ${review.model}`);
    console.log(`${"─".repeat(70)}\n`);

    if (review.error) {
      console.error(`❌ ${review.error}`);
    } else {
      console.log(review.result);
    }
  }

  const duration = ((Date.now() - startTime) / 1000).toFixed(1);

  console.log(`\n${"═".repeat(70)}`);
  console.log(`✅ ${reviewType.toUpperCase()} peer review complete! (${duration}s)`);
  console.log(`${"═".repeat(70)}\n`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
