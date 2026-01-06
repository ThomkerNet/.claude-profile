#!/usr/bin/env bun
/**
 * AI Peer Review - Multi-model code/plan review via Copilot CLI
 * Reviews the most recent plan or issue using multiple AI models
 */

import { readFileSync, readdirSync, statSync, writeFileSync, mkdtempSync, rmSync } from "fs";
import { resolve, basename, join } from "path";
import { exec } from "child_process";
import { promisify } from "util";
import { tmpdir } from "os";

const execAsync = promisify(exec);

interface ReviewConfig {
  models: Array<{
    name: string;
    id: string;
    description: string;
  }>;
  focusArea: string;
}

const REVIEW_CONFIG: ReviewConfig = {
  models: [
    {
      name: "ChatGPT",
      id: "gpt-5.1",
      description: "Advanced reasoning and practical insights",
    },
    {
      name: "Gemini Pro",
      id: "gemini-3-pro-preview",
      description: "Multi-modal understanding and novel perspectives",
    },
    {
      name: "Claude Opus",
      id: "claude-opus-4.5",
      description: "Comprehensive analysis and edge case detection",
    },
  ],
  focusArea: "code architecture, security, feasibility, and improvements",
};

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

  // Search for recent plans
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
    console.error(
      "No plans or issues found. Create a plan first or specify a file path."
    );
    process.exit(1);
  }

  // Return most recently modified file
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
  model: { name: string; id: string; description: string },
  content: string
): Promise<{ model: string; result: string; error?: string }> {
  const reviewPrompt = `Please conduct a thorough peer review of the following plan/architecture document, focusing on:
- ${REVIEW_CONFIG.focusArea}
- Potential pitfalls and edge cases
- Best practices alignment
- Feasibility concerns
- Security implications if applicable
- Suggestions for improvement

Document to review:
---
${content}
---

Provide a structured review with clear sections for strengths, weaknesses, and recommendations.`;

  const startTime = Date.now();

  // Validate model ID against allowlist
  const VALID_MODELS = ["gpt-5.1", "gemini-3-pro-preview", "claude-opus-4.5"];
  if (!VALID_MODELS.includes(model.id)) {
    return {
      model: model.name,
      result: "",
      error: `Invalid model: ${model.id}`,
    };
  }

  // Create secure temporary directory (cross-platform)
  let tmpDir: string | null = null;

  try {
    tmpDir = mkdtempSync(join(tmpdir(), "copilot-review-"));
    const promptFile = join(tmpDir, "prompt.txt");

    // Write prompt to temp file with restrictive permissions
    writeFileSync(promptFile, reviewPrompt, { mode: 0o600 });

    // Use async exec for true parallelization (non-blocking)
    const cmd = `copilot --model ${model.id} --silent -p "$(cat ${promptFile})"`;
    const { stdout } = await execAsync(cmd, {
      encoding: "utf-8",
      maxBuffer: 10 * 1024 * 1024, // 10MB buffer for large responses
      timeout: 300000, // 5 minute timeout to prevent hangs
    });

    return { model: model.name, result: stdout, error: undefined };
  } catch (error) {
    const errorMsg =
      error instanceof Error ? error.message : "Unknown error occurred";
    return {
      model: model.name,
      result: "",
      error: `Failed to get review from ${model.name}: ${errorMsg}`,
    };
  } finally {
    // Always cleanup temp directory, even on errors
    if (tmpDir) {
      try {
        rmSync(tmpDir, { recursive: true, force: true });
      } catch {
        // Silently ignore cleanup errors
      }
    }
  }
}

async function main(): Promise<void> {
  const filePath = process.argv[2];
  const documentPath = findMostRecentPlan(filePath);
  const fileName = basename(documentPath);
  const content = readFileContent(documentPath);

  const startTime = Date.now();

  console.log(`\n${"🔍".repeat(35)}`);
  console.log(`   AI PEER REVIEW - Multi-Model Analysis`);
  console.log(`${"🔍".repeat(35)}\n`);
  console.log(`Document: ${fileName}`);
  console.log(`Models: ${REVIEW_CONFIG.models.map((m) => m.name).join(", ")}`);
  console.log(
    `\n⚡ Starting parallel peer review across ${REVIEW_CONFIG.models.length} AI models...\n`
  );

  // Run reviews in parallel
  const reviews = await Promise.all(
    REVIEW_CONFIG.models.map((model) => reviewWithModel(model, content))
  );

  // Display results in order
  for (const review of reviews) {
    console.log(`\n${"=".repeat(70)}`);
    console.log(`📋 Review by ${review.model}`);
    console.log(`${"=".repeat(70)}\n`);

    if (review.error) {
      console.error(review.error);
    } else {
      console.log(review.result);
    }
  }

  const duration = ((Date.now() - startTime) / 1000).toFixed(1);

  console.log(`\n${"=".repeat(70)}`);
  console.log(`✅ Peer review complete! (${duration}s)`);
  console.log(`${"=".repeat(70)}\n`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
